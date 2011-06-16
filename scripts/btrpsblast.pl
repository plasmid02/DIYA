#!/usr/bin/perl
#--------------------------------------------------------------------------
# ©Copyright 2008
#
# This file is part of DIYA.
#
# DIYA is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# DIYA is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with the diya package.  If not, see <http://www.gnu.org/licenses/>.
#--------------------------------------------------------------------------

use strict;
use File::Spec;
use Bio::SeqIO;
use Getopt::Long;
use POSIX qw(ceil);
use File::Basename;

$ENV{BLASTMAT} = "/common/data/blastmat" if ( ! defined $ENV{BLASTMAT} );

my ($query, $splits, $cleanup, $finishUp, $jobname, $sync, $project, $arch);
my $chunk = 1;
my $output = "stdout.txt";
my $tmp_output_dir = "rpsblast_tmp";

Getopt::Long::Configure("pass_through", "no_auto_abbrev", "no_ignore_case");
GetOptions("i=s"       => \$query,
           "o=s"       => \$output,
           "tmp_dir=s" => \$tmp_output_dir,
           "chunk=i"   => \$chunk,
           "sync"      => \$sync,
           "jobname=s" => \$jobname,
			  "arch=s"    => \$arch,
           "project=s" => \$project);
my $more_args = join(" ", @ARGV);

$tmp_output_dir = File::Spec->rel2abs($tmp_output_dir);
if (-e $tmp_output_dir) {
  die "ERROR:  Please delete temp directory $tmp_output_dir or specify a new one\n";
}
`mkdir $tmp_output_dir`;

die "Unable to find query file $query" if ( ! -e $query );

# Count the number of sequences in the query file.
my $count = `grep '>' $query | wc -l`;
chomp $count;
print STDERR "Counted $count sequences in query $query\n";
$splits = ceil($count / $chunk);
if ($splits>500)
{
    $splits=500;
    if (( $count % 500 )==0)
    {
        $splits=500;
        $chunk=$count/$splits;
    } else
    {
        $chunk=int($count/500)+1;
        $splits=ceil($count/$chunk);
    }
}


# Submit an array job of SPLITS tasks, each doing 
# num_seqs / SPLITS query sequences.
print STDERR "Submitting $splits jobs of $chunk queries.\n";
unless ($jobname){
	$jobname="Job$$-rpsblast";
}
print STDERR "BLASTMAT = $ENV{BLASTMAT}\n";
my $cmd = "qsub ";
$cmd .= "-l arch=$arch " if $arch;
if ($splits > 1)      { $cmd .= "-t 1-$splits "; }
$cmd .=   "-cwd -o rpsblast.stdout -e rpsblast.stderr " .
	       "-N \"$jobname\" ";
if ($project) { $cmd .= "-P $project "; }
$cmd .=   "/common/bin/rpsblast_runner.pl " .
          "-i $query "                            .
          "-o $output "                           .
          "--chunk $chunk ";
if ($main::LOCALDATA) { $cmd .= "--localdata $main::LOCALDATA "; }
$cmd .=   "$more_args";
print STDERR "qsub cmd:  $cmd\n";
system($cmd);

my ($base_outputname, $outputpath) = fileparse($output);

## create cleanup script.
my $cleanfn = "cleanup.sh";
open (OUTPUT, ">$cleanfn");
print OUTPUT <<EOF;
#!/bin/sh
#\$ -q all.q

echo "waiting for jobs to finish"

cat $tmp_output_dir/$base_outputname.* > $output
rm $tmp_output_dir/$base_outputname.*
rmdir $tmp_output_dir
echo "Done."
EOF
close OUTPUT;

`chmod +x $cleanfn`;

$finishUp = "qsub -cwd -N \"$jobname.cleanup\" -hold_jid \"$jobname\" -o batchblast.stdout -e batchblast.stderr ";
if ($sync) { $finishUp .= "-sync y "; }
$finishUp .= " $cleanfn";
system($finishUp);

`rm $cleanfn`;

__END__