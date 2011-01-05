#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;

# options

# --config
# --in
# --format
# --worksheet
# --out
# --xslt

# --set x=y
# --delineator x=y
# --include

# --verbose
# --quiet

# --help
# --version

my %options = ( 
	config=>[], 	set=>[], 	delineator=>[], 
	include=>[],
	noise=>1, 	in=>undef, 	out=>undef, 
	xslt=>undef, 	format=>undef,	worksheet=>undef, 
);

Getopt::Long::Configure("permute");

my $show_help;
my $show_version;
my $verbose;
my $quiet;
GetOptions( 
	'help|?' => \$show_help,
	'version' => \$show_version,

	'verbose+' => \$verbose,
	'quiet' => \$quiet,

	'in=s' => \$options{"in"},
	'out=s' => \$options{"out"},
	'xslt=s' => \$options{"xslt"},
	'format=s' => \$options{"format"},
	'worksheet=i' => \$options{"worksheet"},

	'config=s' => $options{"config"},
	'include=s' => $options{"include"},
	'set=s' => $options{"set"},
	'delineator=s' => $options{"delineator"},
) || show_usage();
show_version() if $show_version;
show_usage( 1 ) if $show_help;
show_usage() if( scalar @ARGV != 0 ); 

$options{noise} = 0 if( $quiet );
$options{noise} = 1+$verbose if( $verbose );

# TODO: Print usage
# TODO: Print version

my $grinder = new Grinder( %options );

$grinder->grind();

exit;








#########################

package Grinder;

use strict;
use warnings;

# set = {} or [] or $
# delineator = {} or [] or $
# include = [] or $

# in (default -)
# out (default -)
# xslt
# format (default csv)
# worksheet (default 1), excel format only
# config = [] or $
# noise (default 1)

sub new
{
	my( $class, %options ) = @_;

	my $self = bless { 
		set => {}, 
		delineator => {},
		include => [],
	}, $class;

	# normal options
	foreach my $opt_key ( keys %options )
	{
		next if( $opt_key eq "set" || $opt_key eq "delineator" );
		if( $opt_key eq "include" ) 
		{
			if( ref( $options{$opt_key} ) eq "" ) 
			{
				push @{$self->{$opt_key}}, $options{$opt_key};
			}
			else
			{
				push @{$self->{$opt_key}}, @{$options{$opt_key}};
			}
			next;
		}
		$self->{$opt_key} = $options{$opt_key};
	}

	if( $options{config} )
	{
		foreach my $config_file ( @{$options{config}} )
		{
			my $config_fh = $self->open_input_file( $config_file );
			my $line_no = 0;
			while( my $line = readline( $config_fh ) )
			{
				$line_no++;	
				chomp $line;
				next if( $line =~ m/^\s*$/ );
				next if( $line =~ m/^\s*#/ );
				if( $line =~ m/^\s*([^:]+):\s*(.*)$/ )
				{
					my( $left, $right ) = ( $1, $2 );
					$right=~s/\s*$//;
					if( $left eq "set" || $left eq "delineator" )
					{
						my( $id, $value ) = split( /=/, $right );
						$self->{$left}->{$id} = $value;
					}
					elsif( $left eq "include" )
					{
						push @{$self->{include}}, $right;
					}
					elsif( !defined $options{$left} )
					{
						# second definition in a config over-writes
						# but does not over-write passed-in option
						$self->{$left} = $right;
					}
					next;
				}
						
				$self->message( "Syntax error in config file '$config_file' at line #$line_no.", 1 );
				$self->message( "Line #$line_no: $line", 2 );
			}

			close( $config_fh );
		}
	}

	#  passed-in options overrides config for hash type fields
	foreach my $opt_key ( keys %options )
	{
		my $v = $options{$opt_key};
		if( $opt_key eq "set" || $opt_key eq "delineator" )
		{
			$v = [ $v ] if( ref( $v ) eq "" );	
			if( ref( $v ) eq "ARRAY" )
			{
				foreach my $touple ( @{$v} )
				{
					my( $id, $value ) = split( /=/, $touple );
					$self->{$opt_key}->{$id} = $value;
				}
			}
			else
			{
				foreach my $id ( keys %{$v} )
				{
					$self->{$opt_key}->{$id} = $v->{$id};
				}
			}
			next;
		}

	}

	$self->{format} = "csv" unless defined $self->{format};
	$self->{noise} = 1 unless defined $self->{noise};
	$self->{in} = "-" unless defined $self->{in};
	$self->{out} = "-" unless defined $self->{out};
	$self->{tmp_dir} = "/tmp" unless defined $self->{tmp_dir};
	$self->{xslt_proc} = '/usr/bin/xsltproc @@XSL@@ @@XML@@' unless defined $self->{xslt_proc};

	return $self;
}

sub open_input_file
{
	my( $self, $filename ) = @_;

	my $fh;

	if( $filename eq "-" )
	{
		$fh = *STDIN;
		binmode( $fh, ":utf8" );
	}
	else
	{
		open( $fh, "<:utf8", $filename ) || $self->error( "Failed to open '$filename' for reading: $!" );
	}
	$self->message( "Opened '$filename' for reading.", 2 );

	return $fh;
}

sub open_output_file
{
	my( $self, $filename ) = @_;

	my $fh;

	if( $filename eq "-" )
	{
		$fh = *STDOUT;
		binmode( $fh, ":utf8" );
	}
	else
	{
		open( $fh, ">:utf8", $filename ) || $self->error( "Failed to open '$filename' for writing: $!" );
	}
	$self->message( "Opened '$filename' for writing.", 2 );

	return $fh;
}

sub close_file
{
	my( $self, $file_handle, $filename ) = @_;

	if( !close( $file_handle ) ) 
	{
		$self->message( "Could not close a file handle on $filename: $!", 1 );
	}
	$self->message( "Closed '$filename'.", 2 );
}

sub unlink_file
{
	my( $self, $filename ) = @_;

	if( !unlink( $filename ) ) 
	{
		$self->message( "Could not unlink $filename: $!", 1 );
	}
	$self->message( "Unlinked '$filename'.", 2 );
}


sub debug
{
	my( $self ) = @_;

	use Data::Dumper;
	print STDERR Dumper( $self );
}

sub error
{
	my( $self, $msg ) = @_;

	print STDERR "Grinder Error: $msg\n";
	exit 1;
}

sub message
{
	my( $self, $msg, $priority ) = @_;

	if( $priority <= $self->{noise} )
	{
		print STDERR "$msg\n";
	}
}

sub grind
{
	my( $self ) = @_;

	# could take extra options to over-ride current ones, esp in & out

	my $in_fh = $self->open_input_file( $self->{in} );

	my $xml_file;
	if( defined $self->{xslt} && $self->{xslt} ne "" )
	{
		$xml_file = $self->{tmp_dir}."/grinder.$$.xml";
	}
	else
	{
		$xml_file = $self->{out};
	}

	my $xml_out_fh = $self->open_output_file( $xml_file );

	$self->{parse} = { rows=>0, set=>{} };	
	foreach my $k ( keys %{ $self->{set} } ) { $self->{parse}->{set}->{$k} = $self->{set}->{$k}; }

	if( $self->{format} eq "excel" ) { $self->process_excel( $in_fh, $xml_out_fh ); }
	elsif( $self->{format} eq "csv" ) { $self->process_csv( $in_fh, $xml_out_fh ); }
	elsif( $self->{format} eq "tsv" ) { $self->process_tsv( $in_fh, $xml_out_fh ); }
	elsif( $self->{format} eq "psv" ) { $self->process_psv( $in_fh, $xml_out_fh ); }
	else { $self->error( "Unknown format '".$self->{format}."'" ); }

	#  TODO:csv
	# TODO:psv
	# TODO:tsv


	# Output end of XML file
	print { $xml_out_fh } <<END;
</grinder-data>
END
	$self->close_file( $xml_out_fh, $xml_file );
	$self->close_file( $in_fh, $self->{in} );



	# If no XSLT then we are done
	if( !defined $self->{xslt} || $self->{xslt} eq "" )
	{
		exit;
	}


	# Read include files
	my @lines = ();
	foreach my $inc_file ( @{$self->{include}} )
	{
		my $inc_fh = $self->open_input_file( $inc_file );
		while( my $line = readline( $inc_fh ) ) { push @lines, $line; }
		$self->close_file( $inc_fh, $inc_file );
	}
	my $include = join( '', @lines );


	# Process XSLT
	
	my $cmd = $self->{xslt_proc};
	$cmd =~ s/\@\@XML\@\@/$xml_file/g;
	$cmd =~ s/\@\@XSL\@\@/$self->{xslt}/g;

	my $xsltproc;
	open( $xsltproc, "-|:utf8", $cmd ) || $self->error( "Failed to exec '$cmd': $!" );
	$self->message( "Executed '$cmd' for writing.", 2 );

	my $out_fh = $self->open_output_file( $self->{out} );
	
	while( my $line = readline( $xsltproc ) )
	{
		$line =~ s/<!--TOP-->/$include/g;
		print { $out_fh } $line;
	}	

	$self->close_file( $out_fh, $self->{out} );	
	$self->close_file( $xsltproc, $cmd );	

	$self->unlink_file( $xml_file );	
}

sub process_row
{
	my( $self, $out, $cells ) = @_;

	# Skip empty rows
	my $empty = 1;
	foreach my $cell ( @{$cells} )
	{
		if( defined $cell && $cell ne "" ) { $empty = 0; last; }
	}
	return if( $empty );

	# *STAR directive fields
	if( substr( $cells->[0],0,1 ) eq "*" )
	{
		if( $cells->[0] eq "*SET" )
		{
			$self->{parse}->{set}->{$cells->[1]} = $cells->[2];
		}
		else
		{
			$self->message( "Unknown * directive: ".$cells->[0] );
		}
		return;
	}

	# Read headings
	if( !defined $self->{parse}->{fields} )
	{
		my $fields = {};
		foreach my $cell ( @{$cells} )
		{
			if( !defined $cell ) 
			{
				push @{$self->{parse}->{fields}}, undef;
				next;
			}
			$cell =~ s/^\s+//;
			$cell =~ s/\s+$//;
			if( $cell eq "" )
			{
				push @{$self->{parse}->{fields}}, undef;
				next;
			}
			if( defined $fields->{$cell} )
			{
				$self->message( "Duplicate column heading '$cell'", 1 );
				next;
			}
			push @{$self->{parse}->{fields}}, $cell;
			$fields->{$cell} = 1;
		}

		# Output Header
		print { $out } <<END;
<?xml version="1.0" encoding='utf-8'?>
<grinder-data xmlns="http://purl.org/openorg/grinder/ns/">
END

		return;
	}

	print { $out } "  <row>\n";
	for my $i ( 0..(scalar @{$self->{parse}->{fields}} - 1 ) )
	{
		my $field = $self->{parse}->{fields}->[$i];
		next if !defined $field;
	
		my $value = $cells->[$i];
		next if !defined $value;

		$value =~ s/^\s+//;
		$value =~ s/\s+$//;

		my @values;
		if( $self->{delineator}->{$field} )
		{
			my $del = $self->{delineator}->{$field};
			@values = split( /\s*$del\s*/, $value );
		}
		else
		{
			@values = ( $value );
		}

		foreach my $value ( @values )
		{
			$value =~ s/&/&amp;/g;
			$value =~ s/>/&gt;/g;
			$value =~ s/</&lt;/g;
			$value =~ s/"/&quot;/g;
			print { $out } "    <$field>$value</$field>\n";
		}
		$self->{parse}->{rows}++;
	}
	print { $out } "  </row>\n";
	
}

sub process_excel
{
	my( $self, $in, $out ) = @_;

	if( ! eval 'use Spreadsheet::ParseExcel; 1;' ) 
	{
		$self->error( "Failed to load Perl Module: Spreadsheet::ParseExcel" );
	}

	my $parser = Spreadsheet::ParseExcel->new();
	my $workbook = $parser->parse( $in );
	if ( !defined $workbook ) 
	{
		$self->error( "Failed to parse Excel file: ".$parser->error() );
	}

	my $n = $self->{worksheet} || 1;
	my @worksheets = $workbook->worksheets();
	if( !defined $worksheets[$n-1] )
	{
		$self->error( "Workbook does not have a worksheet #$n" );
	}
	my $worksheet = $worksheets[$n-1];

	my ( $row_min, $row_max ) = $worksheet->row_range();
	my ( $col_min, $col_max ) = $worksheet->col_range();

	for my $row ( $row_min .. $row_max ) 
	{
		my @cells = ();
		for my $col ( 0 .. $col_max ) 
		{
			my $cell = $worksheet->get_cell( $row, $col );
			my $v;
			if( $cell ) { $v = $cell->value(); };
			push @cells, $v;
		}
		$self->process_row( $out, \@cells );
	}
}


