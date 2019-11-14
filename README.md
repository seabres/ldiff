# ldiff

Generate differences between two LDIF files

This script reads two RFC 2849 LDIF data description files and writes a series of change records to stdout that describe how to go from the first to the second. It determines the correct order to add and remove entries so that the LDAP tree structure isn't violated.

Sample usage:
$ slapcat -l old.ldif
$ sed s/Bob/Robert/g <old.ldif >new.ldif
$ ldiff old.ldif new.ldif | ldapmodify

Original Source: https://www.fruit.je/download/ldiff/
