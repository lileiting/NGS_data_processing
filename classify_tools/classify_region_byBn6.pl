#!/usr/bin/env perl
# By Sunhh. (hs738@cornell.edu)
# Use blastn -outfmt '6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore qlen slen sstrand staxids sscinames sskingdoms stitle'
#   result to type regions in the query into Eukaryota or not.
# 2013-10-17 Version 1.
# 2013-11-01 Edit to assign Include/Exclude kingdoms.
# 2014-03-04 Fix a bug in which we fail to classify some end-to-end alignments. 
use strict;
use warnings;
use Getopt::Long;
my %opts;

GetOptions(
	\%opts,
	"byHsp!",
	"joinInEx:s", "maxUn:i",
	"out:s",
	"InPlastid!",
	"InList:s", "ExList:s",
	"txid2KingList:s",
	"help!"
);

sub writeFH {
	my $fname = shift;
	my $tfh;
	open $tfh,'>',"$fname" or die "$!\n";
	return $tfh;
}
# oFmt='6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore qlen slen sstrand staxids sscinames sskingdoms stitle'
#         0      1      2      3      4        5       6      7    8      9    10     11       12   13   14      15      16        17         18
# Pre configuration.
my $only1Hit = ($opts{byHsp}) ? 0 : 1 ; # 如果指定这个参数为1 (Not using -byHsp parameter), 同一个query区间, 只会计算一次同一个Hit的cover, 这样如果query在Hit内重复出现(多个hsp), 这个Hit对该query单元的支持贡献也只有一次; 关闭为1; Not used now. 
defined $opts{maxUn} or $opts{maxUn} = 1;

my %skingdom=qw(
NA        0
Viruses   1
Bacteria  2
Archaea   3
rDNA           4
Chloroplast    5
Mitochondrion  6
Plastid        7
Eukaryota      8
Satellite      9
Bacteria;Eukaryota  10
Eukaryota;Viruses   11
);
my %isInEx=qw(
NA        Ex
Viruses   Ex
Bacteria  Ex
Archaea   Ex
Eukaryota In
Satellite In
Chloroplast    Ex
Mitochondrion  Ex
Plastid        Ex
rDNA           Ex
); # Should be excluded or included.

my %txid2King; 
if (defined $opts{txid2KingList}) {
	my $tfh = &openFH($opts{txid2KingList}, '<'); 
	while (<$tfh>) {
		my ($id,$kn) = (split)[0,1]; 
		defined $skingdom{$kn} or $skingdom{$kn} = -100; 
		$txid2King{$id} = $kn; 
	}
	close $tfh; 
}#End if -txid2KingList


if ($opts{InPlastid}) {
	$isInEx{'Chloroplast'} = 'In';
	$isInEx{'Mitochondrion'} = 'In';
	$isInEx{'Plastid'} = 'In';
}
if (defined $opts{InList}) {
	for my $tK (split(/:/, $opts{InList})) {
		defined $skingdom{$tK} or do { warn "[Err]No kingdom [$tK] defined. \n"; };
		$isInEx{$tK} = 'In';
		warn "[Rec]Subject kingdom [$tK] is included.\n";
	}
}
if (defined $opts{ExList}) {
	for my $tK (split(/:/, $opts{ExList})) {
		defined $skingdom{$tK} or do { warn "[Err]No kingdom [$tK] defined. \n"; };
		$isInEx{$tK} = 'Ex';
		warn "[Rec]Subject kingdom [$tK] is excluded.\n";
	}
}


sub usage {
	my $version = "v1.0";
	my $last_time = "2013-10-17";
	$last_time = '2013-10-24';
	my $tKK = join( ":", sort { $skingdom{$a} <=> $skingdom{$b} } keys %skingdom );
	my $tII = join( ":", sort { $skingdom{$a} <=> $skingdom{$b} } grep { $isInEx{$_} eq "In" } keys %isInEx );
	my $tEE = join( ":", sort { $skingdom{$a} <=> $skingdom{$b} } grep { $isInEx{$_} eq "Ex" } keys %isInEx );

	print STDOUT <<INFO;
##########################################################################
# perl $0 in.bn6
##########################################################################
# Type query regions by the blastn to nt result.
# oFmt='6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore qlen slen sstrand staxids sscinames sskingdoms stitle'
##########################################################################
# Self use currently.
# Version       : $version
# Last modified : $last_time
# Contact       : hs738\@cornell.edu
##########################################################################
# -help
#
# -byHsp     Query region coverage is calculated by HSP instead of by Hit.
#             The default mode is by Hit.
#             Not used now.
#
# -txid2KingList [filename] File to tell sbjct txid to kingdom class. Format: TXID\\tKingdom\n
#
# -joinInEx  [out file name] joined adjacent In/Excluding units with similar types.
# -maxUn     [integer][$opts{maxUn}] Max number of "Un" type gap between adjacent typed regions.
# -InPlastid [Boolean] Include plastids instead of excluding them.
#             Could be replaced by -InList & -ExList;
#
# -InList    [String] [Kingdom1:Kingdom2:...] Kingdoms to be included.
# -ExList    [String] [Kingdom1:Kingdom2:...] Kingdoms to be excluded. Overwrite -InList
##########################################################################
# Kingdom list: $tKK
# Included    : $tII
# Excluded    : $tEE
#   NA here means the query hits a database sequence with no taxonomy information.
#   Usually they are artificial sequences.
##########################################################################
INFO
	exit 1;
}#End for usage.

if (-t and !@ARGV) {
	&usage();
} elsif ( $opts{help} ) {
	&usage();
}

my $is_joinInEx=0;
my $joinInExFH;
defined $opts{joinInEx} and do { $joinInExFH = &writeFH( $opts{joinInEx} ); $is_joinInEx = 1; };
my $oFH = \*STDOUT;
defined $opts{out} and $oFH = &writeFH( $opts{out} );


# oFmt='6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore qlen slen sstrand staxids sscinames sskingdoms stitle'
#         0      1      2      3      4        5       6      7    8      9    10     11       12   13   14      15      16        17         18
# Pre configuration.

my %qBlks; # {qid}=>[qstart, qend, skingdom_class]
my %qLen; # {qid}=>query_length
my %dvd_site; # {qid}{block-edge}=>1
# Divide query into minimum block units that should be intact in any alignment.
while (<>) {
	/^qseqid\t/ and next;
	chomp;
	my @ta = split(/\t/, $_);
	#### Do some filter if needed to remove un-reliable alignments.
	# Filtering work should be done here instead of later.
	# I prefer to use all acceptable hsp instead of top hits or top hsp, because the sequence length varies and because I limit number of hits when blasting.
	#### Record query blocks assigned to a kingdom_class.
	my $qid = $ta[0]; # Query name
	my $sid = $ta[1]; # Hit name
	my $skd = $ta[17]; # Hit kingdom class
	my $sTXID = $ta[15]; 
	defined $txid2King{$sTXID} and $skd = $txid2King{$sTXID}; 
	my $stitle = $ta[18]; # Hit definition line.
	if      ( $skd eq 'N/A' ) {
		$skd='NA';
	} elsif ( $stitle =~ m/\bchloroplast\b/i ) {
		# $stitle !~ m/ribosom/i and $skd='Chloroplast';
		$skd='Chloroplast';
	} elsif ( $stitle =~ m/\b(?:mitochondrial|mitochondrion)\b/i ) {
		# $stitle !~ m/ribosom/i and $skd='Mitochondrion';
		$skd='Mitochondrion';
	} elsif ( $stitle =~ m/\b(?:plastid)\b/i ) {
		$skd='Plastid';
	} elsif ( $stitle =~ m/\b(?:rDNA|rRNA|ribosomal RNA|ribosomal DNA)\b/i ) {
		$skd='rDNA';
	} elsif ( $skd eq 'Eukaryota' and $stitle =~ m/\b(?:Satellite)\b/i ) {
		$skd='Satellite';
	}
	my ($qs, $qe) = @ta[6,7]; # Query start and end
	my $qlen = $ta[12]; # Query length

	if ($skd =~ m/;/) {
		$skd =~ s/;?Eukaryota;?//; 
	}

	defined $skingdom{$skd} or die "[Err] Unknwn kingdom definition.\n[$ta[17]]\n$_\n";
	push( @{$qBlks{$qid}}, [$qs, $qe, $skd, $sid] ); # Any other information needed? $qs <= $qe ;
	defined $qLen{$qid} or $qLen{$qid} = $ta[12];
	for my $tp ($qs, $qe) {
		defined $dvd_site{$qid}{$tp} or $dvd_site{$qid}{$tp} = 1;
	}
}
warn "[Msg] file read in.\n";


# my %qUnit; # Or I will directly print them out to save memory usage.
print {$oFH} join("\t", qw/qseqid qlen qstart qend qspan KingdomCounts InExcludeCounts/)."\n";
if ( $is_joinInEx == 1 ) {
	print {$joinInExFH} join("\t", qw/qseqid qlen qstart qend qspan KingdomCounts InExcludeCounts/)."\n";
}


for my $qid (keys %dvd_site) {
warn "[Msg]Processing scaff [$qid]\n";
	## Make minimum block units for each query.
	my @qpoints = sort { $a<=>$b } keys %{ $dvd_site{$qid} }; # Sort block boundary sites.
	$qpoints[0] > 1 and unshift(@qpoints, 1);
	$qpoints[-1] < $qLen{$qid} and push(@qpoints, $qLen{$qid});
	my @qMinBlks ; # Initialize minimum blocks. [qstart, qend, {{skingdom=>nCount}}, {hitName=>1} ]
	POINTS:
	for (my $i=0; $i<$#qpoints; $i++) {
		$qpoints[$i+1] == $qpoints[$i]+1 and next POINTS;
		push(@qMinBlks, [ @qpoints[ $i, $i+1 ] ]); # Here the boundary site might overlap to the neighbour.
	}
	## Give type counts (contributions) for each unit.
	my @qSrtBlks = sort { $a->[0]<=>$b->[0] || $a->[1]<=>$b->[1] || $skingdom{$a->[2]} <=> $skingdom{$b->[2]} } @{ $qBlks{$qid} }; # Sort query aligned blocks for following comparison.
	UNIT:
	for (my $minI = 0; $minI < @qMinBlks; $minI++) {
		my $minE = $qMinBlks[$minI]; # [ qstart, qend, {{skingdom=>nCount}} ]
		BLOC:
		for (my $j=0; $j<@qSrtBlks; $j++) {
			my $srtE = $qSrtBlks[$j]; # [ qstart, qend, skingdom, hitName ]
			if      ( $minE->[1] <= $srtE->[0] ) {
				# unit is in upstream of the current first block.
				# go to next unit.
				next UNIT;
			} elsif ( $minE->[0] < $srtE->[1] ) {
				# unit is in the current first block.
				# record and next block.
				if ( $only1Hit ) {
					defined $minE->[3]{ $srtE->[3] } or $minE->[2]{ $srtE->[2] } ++;
					$minE->[3]{ $srtE->[3] } ++;
				}else{
					$minE->[2]{ $srtE->[2] } ++;
				}
				next BLOC;
			} else {
				# unit is in downstream of the current first block.
				; 
			}
		}#End BLOC:for
	}#End UNIT:for

	# Save the final classification.
	# $qUnit{$qid} = [@qMinBlks];
	# Or directly print them out to save memory usage.
	my @combInEx;
	for my $tr1 (@qMinBlks) {
		# [qstart, qend, {{skingdom=>nCount}} ]
		my (@oskd, @oInEx);
		my (@j_oskd, @j_oInEx); # Edit here.
		if (!defined $tr1->[2]) {
			# Not mapped by any hit
			@oskd  = ("Un:0");
			@oInEx = ("In:0");
		}else{
			#
			# my @skds = sort { $tr1->[2]{$b} <=> $tr1->[2]{$a} || $skingdom{$a}<=>$skingdom{$b} } keys %{ $tr1->[2] };
			my @skds = sort { $skingdom{$a}<=>$skingdom{$b} } keys %{ $tr1->[2] };
			my %nInEx;
			for my $skd (@skds) {
				push( @oskd, join(":","$skd",$tr1->[2]{$skd}) );
				$nInEx{ $isInEx{$skd} } += $tr1->[2]{$skd};
			}
			for my $ie (sort { $nInEx{$b} <=> $nInEx{$a} } keys %nInEx) {
				push( @oInEx, join(":", $ie, $nInEx{$ie}) );
			}
		}
		# print $oFH join("\t", qw/qseqid qlen qstart qend qspan KingdomCounts InExcludeCounts/)."\n";
		print {$oFH} join("\t",
			$qid,
			$qLen{$qid},
			$tr1->[0],
			$tr1->[1],
			$tr1->[1]-$tr1->[0]+1,
			join(";;", @oskd),
			join(";;", @oInEx)
		)."\n";
		if ($is_joinInEx == 1) {
			my ($kR1, $vR1, $kStr1) = &parse1(\@oskd);
			my ($kR2, $vR2, $kStr2) = &parse1(\@oInEx);
			if ( scalar(@combInEx) == 0 ) {
				# Initialize.
#				push( @combInEx,
#					[$tr1->[0],           # qstart
#					$tr1->[1],            # qend
#					[$kR1, $vR1, $kStr1], # [KingdomTypes_Ref, KingdomCounts_Ref, KingdomTypes_String]
#					[$kR2, $vR2, $kStr2]  # [InExcludeTypes_Ref, InExcludeCounts_Ref, InExcludeTypes_String]
#					]
#				);
				push( @combInEx,
					[( $tr1->[0]-1 <= $opts{maxUn} ) ? 1 : $tr1->[0] ,           # qstart
					$tr1->[1],            # qend
					[$kR1, $vR1, $kStr1], # [KingdomTypes_Ref, KingdomCounts_Ref, KingdomTypes_String]
					[$kR2, $vR2, $kStr2]  # [InExcludeTypes_Ref, InExcludeCounts_Ref, InExcludeTypes_String]
					]
				);
			} elsif ( $kStr2 eq 'In' and $vR2->[0] == 0 ) {
				# the current block is unknown.
				push( @combInEx,
					[$tr1->[0],           # qstart
					$tr1->[1],            # qend
					[$kR1, $vR1, $kStr1], # [KingdomTypes_Ref, KingdomCounts_Ref, KingdomTypes_String]
					[$kR2, $vR2, $kStr2]  # [InExcludeTypes_Ref, InExcludeCounts_Ref, InExcludeTypes_String]
					]
				);
			} elsif ( scalar(@combInEx) == 1 and $combInEx[-1][3][2] eq 'In' and $combInEx[-1][3][1][0] == 0 and ($tr1->[0] - 1 <= $opts{maxUn}) ) {
				# This is the 2nd block and the 1st block is SHORT Unknown.
				pop(@combInEx);
				push( @combInEx,
					[1,
					$tr1->[1],
					[$kR1, $vR1, $kStr1],
					[$kR2, $vR2, $kStr2]
					]
				);
			} elsif ( $tr1->[0] - $combInEx[-1][1] - 1 <= $opts{maxUn} ) {
				# This is near the previous block.
				if      ( $combInEx[-1][3][2] eq $kStr2 and ( $combInEx[-1][3][2] ne 'In' or $combInEx[-1][3][1][0] > 0 ) ) {
					# Same InEx class, so renew the last element.
					&renewEle( $combInEx[-1] ,
						[ $tr1->[0], $tr1->[1], [$kR1, $vR1, $kStr1], [$kR2, $vR2, $kStr2] ]
					);
				} elsif ( $combInEx[-1][3][2] eq 'In' and $combInEx[-1][3][1][0] == 0 ) {
					# The previous one is Unknown.
					if ( scalar(@combInEx) > 1 and ($tr1->[0] - $combInEx[-2][3][1] - 1 <= $opts{maxUn}) and $combInEx[-2][3][2] eq $kStr1 ) {
						# The one before previous "unkown" is near enough, and same to the current one.
						pop(@combInEx); # Remove the previous "unkown" record. then renew the last element.
						&renewEle( $combInEx[-1] ,
							[ $tr1->[0], $tr1->[1], [$kR1, $vR1, $kStr1], [$kR2, $vR2, $kStr2] ]
						);
					} else {
						# Should be a new block.
						push( @combInEx,
							[$tr1->[0],
							$tr1->[1],
							[$kR1, $vR1, $kStr1],
							[$kR2, $vR2, $kStr2]
							]
						);
					}#End if
				} else {
					# Just push a new record.
					push( @combInEx,
						[$tr1->[0],
						$tr1->[1],
						[$kR1, $vR1, $kStr1],
						[$kR2, $vR2, $kStr2]
						]
					);
				}
			} else {
				# Just push a new record.
				push( @combInEx,
					[$tr1->[0],
					$tr1->[1],
					[$kR1, $vR1, $kStr1],
					[$kR2, $vR2, $kStr2]
					]
				);
			}# End if ( scalar(@combInEx) == 0 )
		}# End if ($is_joinInEx == 1)
	}# for my $tr1 # Used to output query units.

	# For combine
	if ( $is_joinInEx == 1 ) {
		if ( $qLen{$qid} - $combInEx[-1][1] <= $opts{maxUn} ) {
			# The last block unit is near the tail.
			$combInEx[-1][1] = $qLen{$qid};
		}
		if ( $combInEx[-1][3][2] eq 'In' and $combInEx[-1][3][1][0] == 0 and ($qLen{$qid} - $combInEx[-1][0] <= $opts{maxUn}) ) {
			# The last block unit is SHORT Unknown.
			pop(@combInEx);
			$combInEx[-1][1] = $qLen{$qid};
		}
		for my $tr2 ( @combInEx ) {
			my (@sdk_str, @inEx_str);
			for (my $i=0; $i<@{$tr2->[2][0]}; $i++) {
				push( @sdk_str , join(":", $tr2->[2][0][$i], sprintf("%.2f", $tr2->[2][1][$i])) );
			}
			for (my $i=0; $i<@{$tr2->[3][0]}; $i++) {
				push( @inEx_str, join(":", $tr2->[3][0][$i], sprintf("%.2f", $tr2->[3][1][$i])) );
			}
			print {$joinInExFH} join("\t",
				$qid,
				$qLen{$qid},
				$tr2->[0],
				$tr2->[1],
				$tr2->[1] - $tr2->[0] + 1,
				join(";;", @sdk_str),
				join(";;", @inEx_str)
			)."\n";
		}# End for my $tr2
	}# End if ( $is_joinInEx == 1 )
}# for my $qid

if ( $is_joinInEx == 1 ) {
	close( $joinInExFH );
}

warn "[Msg]Over.\n";

#############################################################################
###############  End main             #######################################
#############################################################################

#############################################################################
###############  Subroutines          #######################################
#############################################################################

# Parse elements in @oskd and @oInEx
# Input : \@oskd / \@oInEx
# Output: (\@keys, \@values, "k1::k2::k3...")
sub parse1 {
	my $inR=shift;
	my (@tk, @tv);
	for (@$inR) {
		m/^([^:]+):([\d.]+)$/ or die "[Err]Wrong format for KingdomCounts/InExcludeCounts [$_]\n";
		push(@tk, $1);
		push(@tv, $2);
	}
	return(\@tk, \@tv, join(';;', @tk));
}# End sub parse1

# Mean values in [$vR1] and [$vR2]
# 这里的加和规则没办法做成绝对准确，反正每次加和, 分子部分会有1个hit的失真, 分母可能有1bp重复, 就这样吧, 被大分母除一下也就可以参考了；
# 浪费了太多时间考虑这个规则了, 简单一些.
# Input  : ( $vR1 , $vR2 , $size1, $size2 )
# Output : \@average
sub avgVR {
	my ($vr1, $vr2, $size1, $size2) = @_;
	(defined $size1 and $size1 != 0) or $size1 = 1;
	(defined $size2 and $size2 != 0) or $size2 = 1;

	my (@avg);
	for (my $i=0; $i<@$vr1; $i++) {
		push( @avg,
			($vr1->[$i]*$size1+$vr2->[$i]*$size2) / ($size1+$size2)
		);
	}
	return(\@avg);
}# End sub avgVR

# Renew the last element in array @combInEx
# input  : ($combInEx[-1], $toBeAdd_combInEx_ele)
# output : new $combInEx[-1] .
# In fact i do not think we need that return value, because the passed variable is an reference.
sub renewEle {
	my ($er1, $er2) = @_;
	my $size1 = $er1->[1] - $er1->[0] + 1;
	my $size2 = $er2->[1] - $er2->[0] + 1;
#	$er1->[2][1]
#	=
#	&avgVR(
#		$er1->[2][1],
#		$er2->[2][1],
#		$size1,
#		$size2
#	);
	if      ( $er1->[2][2] eq $er2->[2][2] ) {
		$er1->[2][1]
		=
		&avgVR(
			$er1->[2][1],
			$er2->[2][1],
			$size1,
			$size2
		);
	} elsif ( $er1->[2][0][-1] ne 'COMB' ) {
		push(@{$er1->[2][0]}, 'COMB');
		push(@{$er1->[2][1]}, 0);
		$er1->[2][2] .= ";;COMB";
	}

	$er1->[3][1] = &avgVR(
		$er1->[3][1],
		$er2->[3][1],
		$size1,
		$size2
	);
	$er1->[0] > $er2->[0] and $er1->[0] = $er2->[0];
	$er1->[1] < $er2->[1] and $er1->[1] = $er2->[1];
	return($er1);
}# End sub renewEle

sub openFH ($$) {
	my $f = shift; 
	my $type = shift; 
	my %goodFileType = qw(
		<       read
		>       write
		read    read
		write   write
	); 
	defined $type or $type = 'read'; 
	defined $goodFileType{$type} or die "[Err]Unknown open method tag [$type].\n"; 
	$type = $goodFileType{$type}; 
	local *FH; 
	# my $tfh; 
	if ($type eq 'read') {
		if ($f =~ m/\.gz$/) {
			open (FH, '-|', "gzip -cd $f") or die "[Err]$! [$f]\n"; 
			# open ($tfh, '-|', "gzip -cd $f") or die "[Err]$! [$f]\n"; 
		} elsif ( $f =~ m/\.bz2$/ ) {
			open (FH, '-|', "bzip2 -cd $f") or die "[Err]$! [$f]\n"; 
		} else {
			open (FH, '<', "$f") or die "[Err]$! [$f]\n"; 
		}
	} elsif ($type eq 'write') {
		if ($f =~ m/\.gz$/) {
			open (FH, '|-', "gzip - > $f") or die "[Err]$! [$f]\n"; 
		} elsif ( $f =~ m/\.bz2$/ ) {
			open (FH, '|-', "bzip2 - > $f") or die "[Err]$! [$f]\n"; 
		} else {
			open (FH, '>', "$f") or die "[Err]$! [$f]\n"; 
		}
	} else {
		# Something is wrong. 
		die "[Err]Something is wrong here.\n"; 
	}
	return *FH; 
}# End sub openFH()

