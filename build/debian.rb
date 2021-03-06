# encoding: utf-8
#  Phusion Passenger - https://www.phusionpassenger.com/
#  Copyright (c) 2013 Phusion
#
#  "Phusion Passenger" is a trademark of Hongli Lai & Ninh Bui.
#
#  Permission is hereby granted, free of charge, to any person obtaining a copy
#  of this software and associated documentation files (the "Software"), to deal
#  in the Software without restriction, including without limitation the rights
#  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#  copies of the Software, and to permit persons to whom the Software is
#  furnished to do so, subject to the following conditions:
#
#  The above copyright notice and this permission notice shall be included in
#  all copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
#  THE SOFTWARE.

require 'build/preprocessor'

ALL_DISTRIBUTIONS  = ["raring", "quantal", "precise", "lucid"]
DEBIAN_NAME        = "ruby-passenger"
DEBIAN_EPOCH       = 1
DEBIAN_ORIG_TARBALL_FILES = lambda { PhusionPassenger::Packaging.debian_orig_tarball_files }

def create_debian_package_dir(distribution)
	require 'time'

	variables = {
		:distribution => distribution
	}

	root = "#{PKG_DIR}/#{distribution}"
	sh "rm -rf #{root}"
	sh "mkdir -p #{root}"
	recursive_copy_files(DEBIAN_ORIG_TARBALL_FILES.call, root)
	recursive_copy_files(Dir["debian.template/**/*"], root,
		true, variables)
	sh "mv #{root}/debian.template #{root}/debian"
	changelog = File.read("#{root}/debian/changelog")
	changelog =
		"#{DEBIAN_NAME} (#{DEBIAN_EPOCH}:#{PACKAGE_VERSION}-1~#{distribution}1) #{distribution}; urgency=low\n" +
		"\n" +
		"  * Package built.\n" +
		"\n" +
		" -- #{MAINTAINER_NAME} <#{MAINTAINER_EMAIL}>  #{Time.now.rfc2822}\n\n" +
		changelog
	File.open("#{root}/debian/changelog", "w") do |f|
		f.write(changelog)
	end
end

task 'debian:orig_tarball' => Packaging::PREGENERATED_FILES do
	if File.exist?("#{PKG_DIR}/#{DEBIAN_NAME}_#{PACKAGE_VERSION}.orig.tar.gz")
		puts "WARNING: Debian orig tarball #{PKG_DIR}/#{DEBIAN_NAME}_#{PACKAGE_VERSION}.orig.tar.gz already exists. " +
			"It will not be regenerated. If you are sure that the orig tarball is outdated, please delete it " +
			"and rerun this task."
	else
		sh "rm -rf #{PKG_DIR}/#{DEBIAN_NAME}_#{PACKAGE_VERSION}"
		sh "mkdir -p #{PKG_DIR}/#{DEBIAN_NAME}_#{PACKAGE_VERSION}"
		recursive_copy_files(DEBIAN_ORIG_TARBALL_FILES.call, "#{PKG_DIR}/#{DEBIAN_NAME}_#{PACKAGE_VERSION}")
		sh "cd #{PKG_DIR} && tar -c #{DEBIAN_NAME}_#{PACKAGE_VERSION} | gzip --best > #{DEBIAN_NAME}_#{PACKAGE_VERSION}.orig.tar.gz"
	end
end

desc "Build Debian source and binary package(s) for local testing"
task 'debian:dev' do
	sh "rm -f #{PKG_DIR}/#{DEBIAN_NAME}_#{PACKAGE_VERSION}.orig.tar.gz"
	Rake::Task["debian:clean"].invoke
	Rake::Task["debian:orig_tarball"].invoke
	case distro = string_option('DISTRO', 'current')
	when 'current'
		distributions = [File.read("/etc/lsb-release").scan(/^DISTRIB_CODENAME=(.+)/).first.first]
	when 'all'
		distributions = ALL_DISTRIBUTIONS
	else
		distributions = distro.split(',')
	end
	distributions.each do |distribution|
		create_debian_package_dir(distribution)
		sh "cd #{PKG_DIR}/#{distribution} && dpkg-checkbuilddeps"
	end
	distributions.each do |distribution|
		sh "cd #{PKG_DIR}/#{distribution} && debuild -F -us -uc"
	end
end

desc "Build Debian source packages to be uploaded to repositories"
task 'debian:production' => 'debian:orig_tarball' do
	if boolean_option('USE_CCACHE', false)
		# The resulting Debian rules file must not set USE_CCACHE.
		abort "USE_CCACHE must be returned off when running the debian:production task."
	end
	if filename = string_option('GPG_PASSPHRASE_FILE')
		filename = File.expand_path(filename)
		if !File.exist?(filename)
			abort "GPG passphrase file #{filename} does not exist!"
		end
		if File.stat(filename).mode != 0100600
			abort "The GPG passphrase file #{filename} must be chmodded 0600!"
		end
		gpg_options = "-p'gpg --passphrase-file #{filename} --no-use-agent'"
	end

	ALL_DISTRIBUTIONS.each do |distribution|
		create_debian_package_dir(distribution)
		sh "cd #{PKG_DIR}/#{distribution} && dpkg-checkbuilddeps"
	end
	ALL_DISTRIBUTIONS.each do |distribution|
		sh "cd #{PKG_DIR}/#{distribution} && debuild -S -sa #{gpg_options} -k#{PACKAGE_SIGNING_KEY}"
	end
end

desc "Clean Debian packaging products, except for orig tarball"
task 'debian:clean' do
	files = Dir["#{PKG_DIR}/*.{changes,build,deb,dsc,upload}"]
	sh "rm -f #{files.join(' ')}"
	sh "rm -rf #{PKG_DIR}/dev"
	ALL_DISTRIBUTIONS.each do |distribution|
		sh "rm -rf #{PKG_DIR}/#{distribution}"
	end
	sh "rm -rf #{PKG_DIR}/*.debian.tar.gz"
end
