/* 
 * Copyright (C) 2004-2012 George Yunaev gyunaev@ulduzsoft.com
 *
 * This library is free software; you can redistribute it and/or modify it 
 * under the terms of the GNU Lesser General Public License as published by 
 * the Free Software Foundation; either version 3 of the License, or (at your 
 * option) any later version.
 *
 * This library is distributed in the hope that it will be useful, but WITHOUT 
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or 
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public 
 * License for more details.
 */

static void libirc_add_to_set (int fd, fd_set *set, int * maxfd)
{
	FD_SET (fd, set);

	if ( *maxfd < fd )
		*maxfd = fd;
}

#if defined (ENABLE_DEBUG)
static void libirc_dump_data (const char * prefix, const char * buf, unsigned int length)
{
	printf ("%s: ", prefix);
	for ( ; length > 0; length -- )
		printf ("%c", *buf++);
}
#endif


/*
 * Finds a separator (\x0D\x0A), which separates two lines.
 */
static int libirc_findcrlf (const char * buf, int length)
{
	int offset = 0;
	for ( ; offset < length; offset++ )
	{
		if ( buf[offset] == 0x0D && offset < length - 1 && buf[offset+1] == 0x0A )
			return offset;
		if ( buf[offset] == 0x0A)
			return offset;
	}

	return 0;
}

static int libirc_findcrlf_offset(const char *buf, int offset, const int length)
{
	for(; offset < length; offset++)
	{
		if(buf[offset] != 0x0D && buf[offset] != 0x0A)
		{
			break;
		}
	}
	return offset;
}

static int libirc_findcrorlf (char * buf, int length)
{
	int offset = 0;
	for ( ; offset < length; offset++ ) 
	{
		if ( buf[offset] == 0x0D || buf[offset] == 0x0A )
		{
			buf[offset++] = '\0';

			if ( offset < (length - 1) 
			&& (buf[offset] == 0x0D || buf[offset] == 0x0A) )
				offset++;

			return offset;
		}
	}

	return 0;
}


static void libirc_event_ctcp_internal (irc_session_t * session, const char * event, const char * origin, const char ** params, unsigned int count)
{
	if ( origin )
	{
		char nickbuf[128], textbuf[256];
		irc_target_get_nick (origin, nickbuf, sizeof(nickbuf));

		if ( strstr (params[0], "PING") == params[0] )
			irc_cmd_ctcp_reply (session, nickbuf, params[0]);
		else if ( !strcmp (params[0], "VERSION") )
		{
			unsigned int high, low;
			irc_get_version (&high, &low);

			sprintf (textbuf, "VERSION libirc by Georgy Yunaev ver.%d.%d", high, low);
			irc_cmd_ctcp_reply (session, nickbuf, textbuf);
		}
		else if ( !strcmp (params[0], "FINGER") )
		{
			sprintf (textbuf, "FINGER %s (%s) Idle 0 seconds", 
				session->username ? session->username : "nobody",
				session->realname ? session->realname : "noname");

			irc_cmd_ctcp_reply (session, nickbuf, textbuf);
		}
		else if ( !strcmp (params[0], "TIME") )
		{
			time_t now = time(0);

#if defined (ENABLE_THREADS) && defined (HAVE_LOCALTIME_R)
			struct tm tmtmp, *ltime = localtime_r (&now, &tmtmp);
#else
			struct tm * ltime = localtime (&now);
#endif
			strftime (textbuf, sizeof(textbuf), "%a %b %d %H:%M:%S %Z %Y", ltime);
			irc_cmd_ctcp_reply (session, nickbuf, textbuf);
		}
	}
}
