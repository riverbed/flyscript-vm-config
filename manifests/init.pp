# Copyright (c) 2013 Riverbed Technology, Inc.
# This software is licensed under the terms and conditions of the MIT License set
# forth at https://github.com/riverbed/flyscript-vm-config/blob/master/LICENSE
# ("License").  This software is distributed "AS IS" as set forth in the License.

stage { 'first': before => Stage['main'] }

class setup {
    exec { "apt-update":
      command => "/usr/bin/sudo apt-get -y update",
    }

    exec { "apt-upgrade":
      #command => "/usr/bin/sudo export DEBIAN_FRONTEND=noninteractive  && /usr/bin/sudo apt-get -y upgrade",
      command => '/usr/bin/sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade'
    }
}
class { "setup": stage => first }
  
class core {
    package { 
      [ "vim", "git-core", "build-essential" ]:
        ensure => installed,
        require => Exec['apt-update', 'apt-upgrade'];
    }
}

class python {
    package { 
      [ "python", "python-setuptools", "python-dev", "python-pip", "sqlite3", 
        "python-matplotlib", "python-imaging", "python-scipy",
        "ipython-notebook", "python-nose", "snmpd", 
        "libxml2-dev", "libxslt1-dev"]:
        ensure => installed;
    }

    package {
      [ "virtualenv", "virtualenvwrapper" ]:
      ensure => installed,
      provider => pip;
    }

    package {
      ["ipython"]:
      provider => pip;
    }
}

class web {
    package { 
      [ "apache2", "libapache2-mod-wsgi", 
        "snmp", "curl", "wget" ]:
          ensure => installed,
          require => Exec['apt-update'];
    }

    file {
      "/etc/apache2/sites-available/flyscript_portal":
        content => template("portal/flyscript_portal.erb"),
        ensure => file,
        require => Package["apache2"];
      "/etc/apache2/sites-enabled/001-flyscript_portal":
        ensure => "/etc/apache2/sites-available/flyscript_portal",
        require => Package["apache2"];
      "/etc/apache2/sites-enabled/000-default":
        ensure => absent,
        require => Package["apache2"];
      "/flyscript/wsgi/flyscript_portal.wsgi":
        content => template("portal/flyscript_portal.wsgi"),
        require => File["/flyscript/wsgi"],
        ensure => file;
      "/var/www":
        ensure => directory,
        owner => "www-data",
        group => "www-data",
        recurse => true;
    }

    service {
        "apache2":
            enable => true,
            ensure => running,
            hasstatus => true,
            require => Package["apache2"],
            subscribe => [ Package[ "apache2", "libapache2-mod-wsgi" ] ],
    }

}

class flyscript {
    package {
      "flyscript":
        ensure => latest,
        provider => pip;
    }

    package { 
      [ "wireshark", "tshark" ]:
        ensure => installed,
        require => Exec['apt-update'];
    }
}

class flyscript_portal {
    package {
      [ "django", "djangorestframework", "markdown", "django-model-utils", 
        "pygeoip", "django-extensions", "pysnmp" ]:
        ensure => installed,
        provider => pip,
        require => Package['python-pip', 'python-dev'];
    }

    package {
      "jsonfield":
        ensure => "0.9.5",
        provider => pip,
        require => Package['python-pip'];
    }

    package {
      "pandas":
        ensure => "0.13.1",
        provider => pip,
        require => Package['python-pip'];
    }

    package {
      "numpy":
        ensure => "1.8.0",
        provider => pip,
        require => Package['python-pip'];
    }

    #    package {
    #      "sharepoint":
    #        ensure => ">=0.3.2,<=0.4",
    #        provider => pip,
    #        require => Package['python-pip'];
    #    }
    #
    #    package {
    #      "python-ntlm":
    #        ensure => "1.0.1",
    #        provider => pip,
    #        require => Package['python-pip'];
    #    }
    #
    #    package {
    #      "lxml":
    #        ensure => ">=3.3.0,<3.4.0",
    #        provider => pip,
    #        require => Package['python-pip'];
    #    }

    file {
      "/flyscript":
        ensure => directory,
        mode => 775,
        require => Package[ 'apache2' ],
        notify => Exec[ 'portal_checkout' ];
      "/flyscript/wsgi":
        ensure => directory,
        mode => 775,
        require => Package[ 'apache2' ];
      "/flyscript/flyscript_portal":
        ensure => directory,
        owner => "www-data",
        group => "www-data",
        recurse => true;
    }

    exec {
      'portal_checkout':
        cwd => '/flyscript',
        command => 'git clone https://github.com/riverbed/flyscript-portal.git flyscript_portal',
        path => '/usr/local/bin:/usr/bin:/bin',
        creates => '/flyscript/flyscript_portal/.git',
        require => Package[ "django", "djangorestframework", "markdown", "django-model-utils", 
        "pygeoip", "django-extensions" ],
        subscribe => File["/flyscript/flyscript_portal"],
        notify => [ Exec['portal_requirements'], 
        ],
        refreshonly => true;
    }

    exec {
      'portal_requirements':
        cwd => '/flyscript/flyscript_portal',
        command => 'sudo pip install -r requirements.txt',
        path => '/flyscript/flyscript_portal:/usr/local/bin:/usr/bin:/bin',
        creates => '/flyscript/flyscript_portal/project/settings/active.py',
        notify => [ Exec['portal_setup'], 
        ],
        refreshonly => true;
    }

    exec {
      'portal_setup':
        cwd => '/flyscript/flyscript_portal',
        command => 'sudo ./bootstrap.py install',
        path => '/flyscript/flyscript_portal:/usr/local/bin:/usr/bin:/bin',
        creates => '/flyscript/flyscript_portal/project/settings/active.py',
        notify => [ Exec['portal_init'], 
        ],
        refreshonly => true;
    }

    exec {
      'portal_init':
        cwd => '/flyscript/flyscript_portal',
        command => 'sudo ./clean --reset --force',
        path => '/flyscript/flyscript_portal:/usr/local/bin:/usr/bin:/bin',
        notify => [ Exec['portal_static_files'], 
        ],
        refreshonly => true;
    }

    exec {
      'portal_static_files':
        cwd => '/flyscript/flyscript_portal',
        command => 'sudo python manage.py collectstatic --noinput',
        path => '/flyscript/flyscript_portal:/usr/local/bin:/usr/bin:/bin',
        creates => '/flyscript/flyscript_portal/static/bootstrap',
        notify => [ Exec['portal_permissions'], 
        ],
        refreshonly => true;
    }

    exec {
      'portal_permissions':
        cwd => '/flyscript/flyscript_portal',
        command => 'sudo chown -R www-data:www-data *',
        path => '/flyscript/flyscript_portal:/usr/local/bin:/usr/bin:/bin',
        notify => [ Service['apache2'],
        ],
        refreshonly => true;
    }
}



include core
include python
include web
include flyscript
include flyscript_portal

