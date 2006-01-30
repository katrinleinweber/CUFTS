## CUFTS::Resources::Wiley
##
## Copyright Todd Holbrook - Simon Fraser University (2005)
##
## This file is part of CUFTS.
##
## CUFTS is free software; you can redistribute it and/or modify it under
## the terms of the GNU General Public License as published by the Free
## Software Foundation; either version 2 of the License, or (at your option)
## any later version.
## 
## CUFTS is distributed in the hope that it will be useful, but WITHOUT ANY
## WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
## FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
## details.
##
## You should have received a copy of the GNU General Public License along
## with CUFTS; if not, write to the Free Software Foundation, Inc., 59
## Temple Place, Suite 330, Boston, MA 02111-1307 USA

package CUFTS::Resources::Wiley;

use base qw(CUFTS::Resources::Base::DOI CUFTS::Resources::Base::Journals);

use Data::Dumper;
use CUFTS::Exceptions qw(assert_ne);

use strict;

## title_list_fields - Controls what fields get displayed and loaded from
## title lists.
##

sub title_list_fields {
	return [qw(
		id
		title
		issn
		e_issn
		
		ft_start_date
		ft_end_date
		vol_ft_start
		vol_ft_end
		iss_ft_start
		iss_ft_end
		journal_url
	)];
}

sub title_list_get_field_headings {
	return [qw(
		title
		issn
		e_issn
		journal_url
		___volume
		___issues
		___year
		___rate
		___ft_format
		___early_view
		___mobile
		___ava
		___inc_freq
		___inc_pages
		___title_change
		___merged_title
		___split_title
		___new_journal
		___new_acq
		___new_online
		___dec_freq
		___dec_pages
		___other
		___status
		___new_to_wiley
		___end
		___start
		___first_year
		___acquired_from
		___backfile
		___backfile_collection
		___comment
	)];
}



sub skip_record {
	my ($class, $record) = @_;
	
	$record->{'issn'} =~ /:99/ and
		return 1;

	defined($record->{'ft_start_date'}) or
		return 1;

	defined($record->{'issn'}) or
		return 1;

	return 0;
}

sub clean_data {
	my ($class, $record) = @_;

	$record->{'issn'} =~ /:99/ and
		return ['Skipping due to non-fulltext backfile entry'];

	defined($record->{'___start'}) or
		return ['Skipping due to missing holdings data'];	
		
	$record->{'title'} =~ s/^"//;
	$record->{'title'} =~ s/"$//;

	$record->{'e_issn'} =~ /\d{4}-\d{3}[\dxX]/ or
		delete $record->{'e_issn'};
		
	my ($start_vol, $start_iss, $start_year) = split /\s*\/\s*/, $record->{'___start'};
	$start_vol =~ /(\d+)\s*-?/ and
		$record->{'vol_ft_start'} = $1;
	$start_iss =~ /(\d+)\s*-?/ and
		$record->{'iss_ft_start'} = $1;
	$start_year =~ /(\d{4})/ and
		$record->{'ft_start_date'} = $1;

	if (defined($record->{'___end'})) {
		my ($end_vol, $end_iss, $end_year) = split /\s*\/\s*/, $record->{'___end'};
		$end_vol =~ /-?\s*(\d+)/ and
			$record->{'vol_ft_end'} = $1;
		$end_iss =~ /-?\s*(\d+)/ and
			$record->{'iss_ft_end'} = $1;
		$end_year =~ /(\d{4})/ and
			$record->{'ft_end_date'} = $1;
	}
	
	print Dumper($record), "\n";
	
	return $class->SUPER::clean_data($record);
}



# --------------------------------------------------------------------------------------------

## build_link* - Builds a link to a service.  Should return an array reference containing
## Result objects with urls and title list records (if applicable).
##


sub build_linkJournal {
	my ($class, $records, $resource, $site, $request) = @_;
	
	defined($records) && scalar(@$records) > 0 or 
		return [];
	defined($resource) or 
		CUFTS::Exception::App->throw('No resource defined in build_linkJournal');
	defined($site) or 
		CUFTS::Exception::App->throw('No site defined in build_linkJournal');
	defined($request) or 
		CUFTS::Exception::App->throw('No request defined in build_linkJournal');

	my @results;

	foreach my $record (@$records) {
		next unless assert_ne($record->issn);

		my $url = 'http://www3.interscience.wiley.com/cgi-bin/issn?DESCRIPTOR=PRINTISSN&VALUE=';
        $url .= substr($record->issn,0,4) . '-' . substr($record->issn,4,4);
		my $result = new CUFTS::Result($url);
		$result->record($record);
		
		push @results, $result;
	}

	return \@results;
}

1;
