<?xml version="1.0"?>
<config>
	<memory_cache>
		<driver>Null</driver>
	</memory_cache>
	<disc_cache>
		<driver>Null</driver>
	</disc_cache>
	<SiteTitle>
		<English>Sample HTTP-VWF site</English>
		<Default>Sample HTTP-VWF site</Default>
	</SiteTitle>

	<!--
		The directory holding this site's templates/ directory.  Replace this
		with the real path, for example /usr/lib/example.com.
	-->
	<root_dir>/usr/lib/example.com</root_dir>

	<!--
		Get keys from https://www.google.com/recaptcha/admin
	-->
	<recaptcha>
		<site_key>YOUR_SITE_KEY_HERE</site_key>
		<secret_key>YOUR_SECRET_KEY_HERE</secret_key>
		<enabled>1</enabled>
	</recaptcha>

	<security>
		<rate_limiting>
			<!--  Hard limit - block completely -->
			<max_requests_hard>150</max_requests_hard>
			<!-- Soft limit - show CAPTCHA -->
			<max_requests>100</max_requests>
			<time_window>60s</time_window>
			<!-- 5 minutes after successful CAPTCHA -->
			<captcha_bypass_duration>300s</captcha_bypass_duration>
		</rate_limiting>
		<!-- CGI::IDS threshold -->
		<ids_threshold>50</ids_threshold>
		<csrf>
			<!-- Generate CSRF token for forms -->
			<enable>1</enable>
			<secret>default_secret</secret>
		</csrf>
	</security>

	<!--
		The site's own settings.  Every one of these is optional, and every one
		has a default: the value the framework used to have written into its
		page script, so that a site that says nothing behaves as it always did.
		See "Site settings" in HTTP::VWF's documentation.

		A list can be written as one string of values separated by commas or
		spaces, as here, or as an element with one child per value.

		Where this site's databases are, as Database::Abstraction reads them
		<database_dir>/usr/lib/example.com/data</database_dir>

		The data modules to load, each handed to every page under the last
		part of its name - so My::Site::Data::bands arrives as bands
		<data_modules>HTTP::VWF::Data::index My::Site::Data::bands</data_modules>

		The languages this site offers.  CGI::Lingua negotiates within the
		list, so a language is only reachable once it is here
		<supported_languages>en-gb fr</supported_languages>

		Addresses allowed through the geo-block, and addresses exempt from
		rate limiting.  It is allow_ips and not allowed_ips: that name is
		CGI::ACL's own constructor argument, and would break the ACL
		<allow_ips>108.44.193.70 127.0.0.1</allow_ips>
		<rate_limit_trusted_ips>127.0.0.1 192.168.1.1</rate_limit_trusted_ips>

		The pages ?page= may load; without this, every page this
		distribution ships may be loaded, except captcha
		<pages>index meta_data</pages>

		The countries refused access
		<blacklist_countries>BY MD RU CN BR UY TR MA VE SA CY CO MX IN RS PK UA XH</blacklist_countries>

		Where the access log is written, and read back by the meta-data page
		<vwflog>/var/log/example.com/vwf.log</vwflog>
	-->
</config>
