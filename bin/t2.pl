#!/usr/bin/perl

# Tests from http://www.juniper.net/techpubs/software/junos/junos94/swconfig-policy/defining-as-path-regular-expressions.html

# AS path is 1234
&testit('1234', '1234', 1);
&testit('1234', '1235');

#Zero or more occurrences of AS number 1234
&testit('1234*', '1234', 1);
&testit('1234*', '1234_1234', 1);
&testit('1234*', '1234_1234_1234', 1);
&testit('1234*', '', 1);

#Zero or one occurrence of AS number 1234
&testit('1234?', '1234', 1);
&testit('1234?', '', 1);
&testit('1234{0,1}', '1234', 1);
&testit('1234{0,1}', '', 1);

#One through four occurrences of AS number 1234
&testit('1234{1,4}', '1234', 1);
&testit('1234{1,4}', '1234_1234', 1);
&testit('1234{1,4}', '1234_1234_1234', 1);
&testit('1234{1,4}', '1234_1234_1234_1234', 1);
&testit('1234{1,4}', '');

#One through four occurrences of AS number 12, followed by one occurrence of AS number 34
&testit('12{1,4}_34', '12_34', 1);
&testit('12{1,4}_34', '12_12_34', 1);
&testit('12{1,4}_34', '12_12_12_34', 1);
&testit('12{1,4}_34', '12_12_12_12_34', 1);
&testit('12{1,4}_34', '78_34');

#Path whose first AS number is 123 and second AS number is either 56 or 78
&testit('123_(56|78)', '123_56', 1);
&testit('123_(56|78)', '123_78', 1);
&testit('123_(56|78)', '123_90');

#Path of any length, except nonexistent, whose second AS number can be anything, including nonexistent
&testit('.*', '');
&testit('.*', '1234', 1);
&testit('.*', '1234_5678', 1);
&testit('.*', '1234_5_6_7_8', 1);

#AS path is 1 2 3
&testit('1_2_3', '1_2_3', 1);
&testit('1_2_3', '1_2_4');

#One occurrence of the AS numbers 1 and 2, followed by one or more occurrences of the number 3
&testit ('1_2_3+', '1_2_3', 1);
&testit ('1_2_3+', '1_2_3_3', 1);
&testit ('1_2_3+', '1_2_3_3_3', 1);
&testit ('1_2_3+', '4_2_3_3_3');

#Path of any length that begins with AS numbers 4, 5, 6
&testit('4_5_6.*', '4_5_6', 1);
&testit('4_5_6.*', '4_5_6_7_8_9', 1);
&testit('4_5_6.*', '9_5_6_7_8_9');

#Path of any length that ends with AS numbers 4, 5, 6
&testit('.*4_5_6', '4_5_6', 1);
&testit('.*4_5_6', '1_2_3_4_5_6', 1);
&testit('.*4_5_6', '9_5_6_7_8_9');

#AS path 5, 12, or 18
&testit('5|12|18', '5', 1);
&testit('5|12|18', '12', 1);
&testit('5|12|18', '18', 1);
&testit('5|12|18', '5_12_18');
&testit('5|12|18', '123');

sub testit {
	my ($as_regexp, $as_path, $pass) = @_;
	return unless ($as_regexp);
	my $internal_result = &as_regexp($as_regexp, $as_path);
	system("./r '$as_regexp' '$as_path'");
	my $external_result;
	if ($? == 0) {
		$external_result = 1;
	}
	else {
		$external_result = undef;
	}

	if ($internal_result != $external_result) {
		print "MISMATCH: AS_REGEXP = $as_regexp, AS_PATH = $as_path, PASS = $pass IR = $internal_result, ER= $external_result\n";
	}
	else {
		print "PASS: AS_REGEXP = $as_regexp, AS_PATH = $as_path, PASS=$pass\n";
	}

}

sub as_regexp {

	my ($as_regexp, $as_path) = @_;
	return unless ($as_regexp);
	return if ($as_regexp=~ m/[^0-9\(\)\[\]\,\.\*\?\{\}\|\_\+]+/);
	use re::engine::RE2 (-max_mem => 1<<15, -strict => 1, -longest_match => 1, -never_nl => 1);
	my $compiled_regexp = qr/$as_regexp/;
	return 1 if ($as_path=~ $compiled_regexp);
	
	return;
}
__END__
	

	return unless ($as_regexp && $as_path);

	my $magic = '(^|[,{}() ]|$)';		# convert all underscores into this pattern
	
	$as_regexp=~s/_/$magic/g;
	
	my $match_regexp = qr/$as_regexp/; print $match_regexp;

	return 1 if ($as_path =~ $match_regexp);

	return;

}
