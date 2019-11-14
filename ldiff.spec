%define name	ldiff
%define release	1.el7
%define version	2.2.0

Summary:	Generate differences between two LDIF files
License:	perl
Name:		%{name}
Version:	%{version}
Release:	%{release}
Group:		System Environment/Base
BuildRoot:	%{_topdir}/BUILDROOT
BuildArch:	noarch
URL:		https://github.com/seabres/ldiff
Packager:	rainer.brestan@gmx.net
Requires:	bash,perl

%description
Generate differences between two LDIF files.

%prep
# empty, because nothing to do

%build
# empty, because nothing to do

%install
# first empty the install root
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT/usr/bin
cp -p ../script/ldiff.pl $RPM_BUILD_ROOT/usr/bin/ldiff
cp -p ../MANIFEST $RPM_BUILD_ROOT/../../BUILD
cp -p ../META.yml $RPM_BUILD_ROOT/../../BUILD

%files
%defattr(-,root,root)
/usr/bin/*
%doc MANIFEST META.yml

%changelog
* Sat Oct 23 2010 fruit.je - 2.1
* Thu Jun 30 2016 Rainer Brestan <rainer.brestan@gmx.net> - 2.2.0-1
- Correct handling of attributes with emtry value on output
- Added interpreter to call it as executable
