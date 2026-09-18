/* Identity gettext shim: atf is not localized.

   The vendored parser uses gettext()/dgettext() for messages that are only
   visible with parse_datetime2's debug flag. */

#ifndef ATF_GETTEXT_H
#define ATF_GETTEXT_H

#define GNULIB_TEXT_DOMAIN "atf"
#define gettext(Msgid) (Msgid)
#define dgettext(Domainname, Msgid) (Msgid)

#endif
