# vim: sw=4:ts=4:et

%define selinux_policyver 3.12.1-181

Name:   drepl_sandbox_selinux
Version:	1.0
Release:	1%{?dist}
Summary:	SELinux policy module for drepl_sandbox

Group:	System Environment/Base		
License:	GPLv2+	
# This is an example. You will need to change it.
URL:		http://HOSTNAME
Source0:	drepl_sandbox.pp
Source1:	drepl_sandbox.if
Source2:	drepl_sandbox_selinux.8


Requires: policycoreutils, libselinux-utils
Requires(post): selinux-policy-base >= %{selinux_policyver}, policycoreutils
Requires(postun): policycoreutils
BuildArch: noarch

%description
This package installs and sets up the  SELinux policy security module for drepl_sandbox.

%install
install -d %{buildroot}%{_datadir}/selinux/packages
install -m 644 %{SOURCE0} %{buildroot}%{_datadir}/selinux/packages
install -d %{buildroot}%{_datadir}/selinux/devel/include/contrib
install -m 644 %{SOURCE1} %{buildroot}%{_datadir}/selinux/devel/include/contrib/
install -d %{buildroot}%{_mandir}/man8/
install -m 644 %{SOURCE2} %{buildroot}%{_mandir}/man8/drepl_sandbox_selinux.8
install -d %{buildroot}/etc/selinux/targeted/contexts/users/


%post
semodule -n -i %{_datadir}/selinux/packages/drepl_sandbox.pp
if /usr/sbin/selinuxenabled ; then
    /usr/sbin/load_policy
    

fi;
exit 0

%postun
if [ $1 -eq 0 ]; then
    semodule -n -r drepl_sandbox
    if /usr/sbin/selinuxenabled ; then
       /usr/sbin/load_policy
       

    fi;
fi;
exit 0

%files
%attr(0600,root,root) %{_datadir}/selinux/packages/drepl_sandbox.pp
%{_datadir}/selinux/devel/include/contrib/drepl_sandbox.if
%{_mandir}/man8/drepl_sandbox_selinux.8.*


%changelog
* Mon Sep  8 2014 YOUR NAME <YOUR@EMAILADDRESS> 1.0-1
- Initial version

