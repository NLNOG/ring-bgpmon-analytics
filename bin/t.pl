#!/usr/bin/perl

use Boost::Graph;
use Data::Dumper;

my ($newpath, $origin, $upstream) = &simplifyPaths($ARGV[0]);
print "NEWPATH = $newpath\nORIGIN = $origin\nUPSTREAM = $upstream\n";

sub simplifyPaths {
        my $paths = shift;
        return unless ($paths);

        my $graph = new Boost::Graph(directed=>1);      # directed graph
        my @paths = split(/,/, $paths);                 # list of all paths

	my @children;		# Storage for directed graph children
        my @newpath;            # Space for new path to be constructed
        my ($node, $origin);    # Current Node and Origin AS

	#Now remove prepended AS nodes from the path, since they'll confuse our graph
        foreach my $path (@paths) {
		#print "INPATH = $path ";
                my @elems = reverse(split(/_/, $path));
		for (my $i=0; $i<$#elems; $i++) {
			if ($elems[$i] == $elems[($i+1)]) {
				splice (@elems, $i, 1);
				$i--;
			}
		}
		#print "OUTPATH = " . join('_', reverse(@elems)) . "\n";
                $origin = $elems[0] unless ($origin);
                $graph->add_path(@elems);
        }

	#Now we can build the graph and work out what the shortest common path is 
        $node = $origin;
        WALKNODES:
        for (my $i=1; $i<$graph->nodecount(); $i++) {
                @children = @{$graph->children_of_directed($node)};
		#print "Investigating " . Dumper(\@children) . "\n";
                if ($#children > 0) {
                        last WALKNODES;
                }
                else { 
                        $node = $children[0];
                        if ($node) {
                                push (@newpath, $node);
                        }
                        else { 
                                last WALKNODES;
                        }
                }
        }
	@newpath = reverse(@newpath);
        return (join('_', @newpath, $origin), $origin, join(',',@children));
}

