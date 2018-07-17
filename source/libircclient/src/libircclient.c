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

#define IS_DEBUG_ENABLED(s)	((s)->options & LIBIRC_OPTION_DEBUG)

#include "portable.c"
#include "sockets.c"

#include "libircclient.h"
#include "session.h"

#include "utils.c"
#include "errors.c"
#include "colors.c"
#include "dcc.c"
#include "ssl.c"


#ifdef _MSC_VER
	/*
	 * The debugger of MSVC 2005 does not like strdup.
	 * It complains about heap corruption when free is called.
	 * Use _strdup instead.
	 */
	#undef strdup
	#define strdup _strdup
#endif


irc_session_t * irc_create_session (irc_callbacks_t	* callbacks)
{
	irc_session_t * session = (irc_session_t*)malloc (sizeof(irc_session_t));

	if ( !session )
		return 0;

	memset (session, 0, sizeof(irc_session_t));
	session->sock = -1;

	if ( libirc_mutex_init (&session->mutex_session)
	|| libirc_mutex_init (&session->mutex_dcc) )
	{
		free (session);
		return 0;
	}

	session->dcc_last_id = 1;
	session->dcc_timeout = 60;

	memcpy (&session->callbacks, callbacks, sizeof(irc_callbacks_t));

	if ( !session->callbacks.event_ctcp_req )
		session->callbacks.event_ctcp_req = libirc_event_ctcp_internal;

	return session;
}

static void free_ircsession_strings (irc_session_t * session)
{
	if ( session->realname )
		free (session->realname);

	if ( session->username )
		free (session->username);

	if ( session->nick )
		free (session->nick);

	if ( session->server )
		free (session->server);

	if ( session->server_password )
		free (session->server_password);

	session->realname = 0;
	session->username = 0;
	session->nick = 0;
	session->server = 0;
	session->server_password = 0;
}

void irc_destroy_session (irc_session_t * session)
{
	free_ircsession_strings( session );
	
	if ( session->sock >= 0 )
		socket_close (&session->sock);

#if defined (ENABLE_THREADS)
	libirc_mutex_destroy (&session->mutex_session);
#endif

	/* 
	 * delete DCC data 
	 * libirc_remove_dcc_session removes the DCC session from the list.
	 */
	while ( session->dcc_sessions )
		libirc_remove_dcc_session (session, session->dcc_sessions, 0);

	free (session);
}


int irc_connect (irc_session_t * session,
			const char * server, 
			unsigned short port,
			const char * server_password,
			const char * nick,
			const char * username,
			const char * realname)
{
	struct sockaddr_in saddr;
	char * p;

	// Check and copy all the specified fields
	if ( !server || !nick )
	{
		session->lasterror = LIBIRC_ERR_INVAL;
		return 1;
	}

	if ( session->state != LIBIRC_STATE_INIT )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		return 1;
	}

	// Free the strings if defined; may be the case when the session is reused after the connection fails
	free_ircsession_strings( session );

	// Handle the server # prefix (SSL)
	if ( server[0] == SSL_PREFIX )
	{
#if defined (ENABLE_SSL)
		server++;
		session->flags |= SESSIONFL_SSL_CONNECTION;
#else
		session->lasterror = LIBIRC_ERR_SSL_NOT_SUPPORTED;
		return 1;
#endif
	}
	
	if ( username )
		session->username = strdup (username);

	if ( server_password )
		session->server_password = strdup (server_password);

	if ( realname )
		session->realname = strdup (realname);

	session->nick = strdup (nick);
	session->server = strdup (server);

	// If port number is zero and server contains the port, parse it
	if ( port == 0 && (p = strchr( session->server, ':' )) != 0 )
	{
		// Terminate the string and parse the port number
		*p++ = '\0';
		port = atoi( p );
	}

	// IPv4 address resolving
	memset( &saddr, 0, sizeof(saddr) );
	saddr.sin_family = AF_INET;
	saddr.sin_port = htons (port);		
	saddr.sin_addr.s_addr = inet_addr( session->server );

    if ( saddr.sin_addr.s_addr == INADDR_NONE )
    {
		struct hostent *hp;
#if defined HAVE_GETHOSTBYNAME_R
		int tmp_errno;
		struct hostent tmp_hostent;
		char buf[2048];

      	if ( gethostbyname_r (session->server, &tmp_hostent, buf, sizeof(buf), &hp, &tmp_errno) )
      		hp = 0;
#else
      	hp = gethostbyname (session->server);
#endif // HAVE_GETHOSTBYNAME_R
		if ( !hp )
		{
			session->lasterror = LIBIRC_ERR_RESOLV;
			return 1;
		}

		memcpy (&saddr.sin_addr, hp->h_addr, (size_t) hp->h_length);
    }

    // create the IRC server socket
	if ( socket_create( PF_INET, SOCK_STREAM, &session->sock)
	|| socket_make_nonblocking (&session->sock) )
	{
		session->lasterror = LIBIRC_ERR_SOCKET;
		return 1;
	}

#if defined (ENABLE_SSL)
	// Init the SSL stuff
	if ( session->flags & SESSIONFL_SSL_CONNECTION )
	{
		int rc = ssl_init( session );
		
		if ( rc != 0 )
		{
			session->lasterror = rc;
			return 1;
		}
	}
#endif
	
    // and connect to the IRC server
    if ( socket_connect (&session->sock, (struct sockaddr *) &saddr, sizeof(saddr)) )
    {
    	session->lasterror = LIBIRC_ERR_CONNECT;
		return 1;
    }

    session->state = LIBIRC_STATE_CONNECTING;
    session->flags = SESSIONFL_USES_IPV6; // reset in case of reconnect
	return 0;
}


int irc_connect6 (irc_session_t * session,
			const char * server, 
			unsigned short port,
			const char * server_password,
			const char * nick,
			const char * username,
			const char * realname)
{
#if defined (ENABLE_IPV6)
	struct sockaddr_in6 saddr;
	struct addrinfo ainfo, *res = NULL;
	char portStr[32], *p;
#if defined (_WIN32)
	int addrlen = sizeof(saddr);
	HMODULE hWsock;
	getaddrinfo_ptr_t getaddrinfo_ptr;
	freeaddrinfo_ptr_t freeaddrinfo_ptr;
	int resolvesuccess = 0;
#endif

	// Check and copy all the specified fields
	if ( !server || !nick )
	{
		session->lasterror = LIBIRC_ERR_INVAL;
		return 1;
	}

	if ( session->state != LIBIRC_STATE_INIT )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		return 1;
	}

	// Free the strings if defined; may be the case when the session is reused after the connection fails
	free_ircsession_strings( session );

	// Handle the server # prefix (SSL)
	if ( server[0] == SSL_PREFIX )
	{
#if defined (ENABLE_SSL)
		server++;
		session->flags |= SESSIONFL_SSL_CONNECTION;
#else
		session->lasterror = LIBIRC_ERR_SSL_NOT_SUPPORTED;
		return 1;
#endif
	}
	
	if ( username )
		session->username = strdup (username);

	if ( server_password )
		session->server_password = strdup (server_password);

	if ( realname )
		session->realname = strdup (realname);

	session->nick = strdup (nick);
	session->server = strdup (server);

	// If port number is zero and server contains the port, parse it
	if ( port == 0 && (p = strchr( session->server, ':' )) != 0 )
	{
		// Terminate the string and parse the port number
		*p++ = '\0';
		port = atoi( p );
	}
	
	memset( &saddr, 0, sizeof(saddr) );
	saddr.sin6_family = AF_INET6;
	saddr.sin6_port = htons (port);	
	
	sprintf( portStr, "%u", (unsigned)port );

#if defined (_WIN32)
	if ( WSAStringToAddressA( (LPSTR)session->server, AF_INET6, NULL, (struct sockaddr *)&saddr, &addrlen ) == SOCKET_ERROR )
	{
		hWsock = LoadLibraryA("ws2_32");

		if (hWsock)
		{
			/* Determine functions at runtime, because windows systems < XP do not
			 * support getaddrinfo. */
			getaddrinfo_ptr = (getaddrinfo_ptr_t)GetProcAddress(hWsock, "getaddrinfo");
			freeaddrinfo_ptr = (freeaddrinfo_ptr_t)GetProcAddress(hWsock, "freeaddrinfo");

			if (getaddrinfo_ptr && freeaddrinfo_ptr)
			{
				memset(&ainfo, 0, sizeof(ainfo));
				ainfo.ai_family = AF_INET6;
				ainfo.ai_socktype = SOCK_STREAM;
				ainfo.ai_protocol = 0;

				if ( getaddrinfo_ptr(session->server, portStr, &ainfo, &res) == 0 && res )
				{
					resolvesuccess = 1;
					memcpy( &saddr, res->ai_addr, res->ai_addrlen );
					freeaddrinfo_ptr( res );
				}
			}
			FreeLibrary(hWsock);
		}
		if (!resolvesuccess)
		{
			session->lasterror = LIBIRC_ERR_RESOLV;
			return 1;
		}
	}
#else
	if ( inet_pton( AF_INET6, session->server, (void*) &saddr.sin6_addr ) <= 0 )
	{		
		memset( &ainfo, 0, sizeof(ainfo) );
		ainfo.ai_family = AF_INET6;
		ainfo.ai_socktype = SOCK_STREAM;
		ainfo.ai_protocol = 0;

		if ( getaddrinfo( session->server, portStr, &ainfo, &res ) || !res )
		{
			session->lasterror = LIBIRC_ERR_RESOLV;
			return 1;
		}
		
		memcpy( &saddr, res->ai_addr, res->ai_addrlen );
		freeaddrinfo( res );
	}
#endif
	
	// create the IRC server socket
	if ( socket_create( PF_INET6, SOCK_STREAM, &session->sock)
	|| socket_make_nonblocking (&session->sock) )
	{
		session->lasterror = LIBIRC_ERR_SOCKET;
		return 1;
	}

#if defined (ENABLE_SSL)
	// Init the SSL stuff
	if ( session->flags & SESSIONFL_SSL_CONNECTION )
	{
		int rc = ssl_init( session );
		
		if ( rc != 0 )
			return rc;
	}
#endif
	
    // and connect to the IRC server
    if ( socket_connect (&session->sock, (struct sockaddr *) &saddr, sizeof(saddr)) )
    {
    	session->lasterror = LIBIRC_ERR_CONNECT;
		return 1;
    }

    session->state = LIBIRC_STATE_CONNECTING;
    session->flags = 0; // reset in case of reconnect
	return 0;
#else
	session->lasterror = LIBIRC_ERR_NOIPV6;
	return 1;
#endif	
}


int irc_is_connected (irc_session_t * session)
{
	return (session->state == LIBIRC_STATE_CONNECTED 
	|| session->state == LIBIRC_STATE_CONNECTING) ? 1 : 0;
}


int irc_run (irc_session_t * session)
{
	if ( session->state != LIBIRC_STATE_CONNECTING )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		return 1;
	}

	while ( irc_is_connected(session) )
	{
		struct timeval tv;
		fd_set in_set, out_set;
		int maxfd = 0;

		tv.tv_usec = 250000;
		tv.tv_sec = 0;

		// Init sets
		FD_ZERO (&in_set);
		FD_ZERO (&out_set);

		irc_add_select_descriptors (session, &in_set, &out_set, &maxfd);

		if ( select (maxfd + 1, &in_set, &out_set, 0, &tv) < 0 )
		{
			if ( socket_error() == EINTR )
				continue;

			session->lasterror = LIBIRC_ERR_TERMINATED;
			return 1;
		}

		if ( irc_process_select_descriptors (session, &in_set, &out_set) )
			return 1;
	}

	return 0;
}


int irc_add_select_descriptors (irc_session_t * session, fd_set *in_set, fd_set *out_set, int * maxfd)
{
	if ( session->sock < 0 
	|| session->state == LIBIRC_STATE_INIT
	|| session->state == LIBIRC_STATE_DISCONNECTED )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		return 1;
	}

	libirc_mutex_lock (&session->mutex_session);

	switch (session->state)
	{
	case LIBIRC_STATE_CONNECTING:
		// While connection, only out_set descriptor should be set
		libirc_add_to_set (session->sock, out_set, maxfd);
		break;

	case LIBIRC_STATE_CONNECTED:
		// Add input descriptor if there is space in input buffer
		if ( session->incoming_offset < (sizeof (session->incoming_buf) - 1) 
		|| (session->flags & SESSIONFL_SSL_WRITE_WANTS_READ) != 0 )
			libirc_add_to_set (session->sock, in_set, maxfd);

		// Add output descriptor if there is something in output buffer
		if ( libirc_findcrlf (session->outgoing_buf, session->outgoing_offset) > 0
		|| (session->flags & SESSIONFL_SSL_READ_WANTS_WRITE) != 0 )
			libirc_add_to_set (session->sock, out_set, maxfd);

		break;
	}

	libirc_mutex_unlock (&session->mutex_session);

	libirc_dcc_add_descriptors (session, in_set, out_set, maxfd);
	return 0;
}


static void libirc_process_incoming_data (irc_session_t * session, size_t process_length)
{
	#define MAX_PARAMS_ALLOWED 10
	char buf[2*512], *p, *s;
	const char * command = 0, *prefix = 0, *params[MAX_PARAMS_ALLOWED+1];
	int code = 0, paramindex = 0;
    char *buf_end = buf + process_length;

	if ( process_length > sizeof(buf) )
		abort(); // should be impossible

	memcpy (buf, session->incoming_buf, process_length);
	buf[process_length] = '\0';

	memset ((char *)params, 0, sizeof(params));
	p = buf;

    /*
     * From RFC 1459:
	 *  <message>  ::= [':' <prefix> <SPACE> ] <command> <params> <crlf>
	 *  <prefix>   ::= <servername> | <nick> [ '!' <user> ] [ '@' <host> ]
	 *  <command>  ::= <letter> { <letter> } | <number> <number> <number>
	 *  <SPACE>    ::= ' ' { ' ' }
	 *  <params>   ::= <SPACE> [ ':' <trailing> | <middle> <params> ]
	 *  <middle>   ::= <Any *non-empty* sequence of octets not including SPACE
	 *                 or NUL or CR or LF, the first of which may not be ':'>
	 *  <trailing> ::= <Any, possibly *empty*, sequence of octets not including
	 *                   NUL or CR or LF>
 	 */

	// Parse <prefix>
	if ( buf[0] == ':' )
	{
		while ( *p && *p != ' ')
			p++;

		*p++ = '\0';

		// we use buf+1 to skip the leading colon
		prefix = buf + 1;

		// If LIBIRC_OPTION_STRIPNICKS is set, we should 'clean up' nick 
		// right here
		if ( session->options & LIBIRC_OPTION_STRIPNICKS )
		{
			for ( s = buf + 1; *s; s++ )
			{
				if ( *s == '@' || *s == '!' )
				{
					*s = '\0';
					break;
				}
			}
		}
	}

	// Parse <command>
	if ( isdigit (p[0]) && isdigit (p[1]) && isdigit (p[2]) )
	{
		p[3] = '\0';
		code = atoi (p);
		p += 4;
	}
	else
	{
		s = p;

		while ( *p && *p != ' ')
			p++;

		*p++ = '\0';

		command = s;
	}

	// Parse middle/params
	while ( *p &&  paramindex < MAX_PARAMS_ALLOWED )
	{
		// beginning from ':', this is the last param
		if ( *p == ':' )
		{
			params[paramindex++] = p + 1; // skip :
			break;
		}

		// Just a param
		for ( s = p; *p && *p != ' '; p++ )
			;

		params[paramindex++] = s;

		if ( !*p )
			break;

		*p++ = '\0';
	}

	// Handle PING/PONG
	if ( command && !strncmp (command, "PING", buf_end - command) && params[0] )
	{
		irc_send_raw (session, "PONG %s", params[0]);
		return;
	}

	// and dump
	if ( code )
	{
		// We use SESSIONFL_MOTD_RECEIVED flag to check whether it is the first
		// RPL_ENDOFMOTD or ERR_NOMOTD after the connection.
		if ( (code == 1 || code == 376 || code == 422) && !(session->flags & SESSIONFL_MOTD_RECEIVED ) )
		{
			session->flags |= SESSIONFL_MOTD_RECEIVED;

			if ( session->callbacks.event_connect )
				(*session->callbacks.event_connect) (session, "CONNECT", prefix, params, paramindex);
		}

		if ( session->callbacks.event_numeric )
			(*session->callbacks.event_numeric) (session, code, prefix, params, paramindex);
	}
	else
	{
		if ( !strncmp (command, "NICK", buf_end - command) )
		{
			/*
			 * If we're changed our nick, we should save it.
             */
			char nickbuf[256];

			irc_target_get_nick (prefix, nickbuf, sizeof(nickbuf));

			if ( !strncmp (nickbuf, session->nick, strlen(session->nick)) && paramindex > 0 )
			{
				free (session->nick);
				session->nick = strdup (params[0]);
			}

			if ( session->callbacks.event_nick )
				(*session->callbacks.event_nick) (session, command, prefix, params, paramindex);
		}
		else if ( !strncmp (command, "QUIT", buf_end - command) )
		{
			if ( session->callbacks.event_quit )
				(*session->callbacks.event_quit) (session, command, prefix, params, paramindex);
		}
		else if ( !strncmp (command, "JOIN", buf_end - command) )
		{
			if ( session->callbacks.event_join )
				(*session->callbacks.event_join) (session, command, prefix, params, paramindex);
		}
		else if ( !strncmp (command, "PART", buf_end - command) )
		{
			if ( session->callbacks.event_part )
				(*session->callbacks.event_part) (session, command, prefix, params, paramindex);
		}
		else if ( !strncmp (command, "MODE", buf_end - command) )
		{
			if ( paramindex > 0 && !strncmp (params[0], session->nick, strlen(session->nick)) )
			{
				params[0] = params[1];
				paramindex = 1;

				if ( session->callbacks.event_umode )
					(*session->callbacks.event_umode) (session, command, prefix, params, paramindex);
			}
			else
			{
				if ( session->callbacks.event_mode )
					(*session->callbacks.event_mode) (session, command, prefix, params, paramindex);
			}
		}
		else if ( !strncmp (command, "TOPIC", buf_end - command) )
		{
			if ( session->callbacks.event_topic )
				(*session->callbacks.event_topic) (session, command, prefix, params, paramindex);
		}
		else if ( !strncmp (command, "KICK", buf_end - command) )
		{
			if ( session->callbacks.event_kick )
				(*session->callbacks.event_kick) (session, command, prefix, params, paramindex);
		}
		else if ( !strncmp (command, "PRIVMSG", buf_end - command) )
		{
			if ( paramindex > 1 )
			{ 
				size_t msglen = strlen (params[1]);

				/* 
				 * Check for CTCP request (a CTCP message starts from 0x01 
				 * and ends by 0x01
				 */
				if ( params[1][0] == 0x01 && params[1][msglen-1] == 0x01 )
				{
					char ctcp_buf[128];

					msglen -= 2;
					if ( msglen > sizeof(ctcp_buf) - 1 )
						msglen = sizeof(ctcp_buf) - 1;

					memcpy (ctcp_buf, params[1] + 1, msglen);
					ctcp_buf[msglen] = '\0';

					if ( msglen >= 4 && !strncasecmp(ctcp_buf, "DCC ", 4) )
						libirc_dcc_request (session, prefix, ctcp_buf);
					else if ( msglen >= 7 && !strncasecmp( ctcp_buf, "ACTION ", 7)
					&& session->callbacks.event_ctcp_action )
					{
						params[1] = ctcp_buf + 7; // the length of "ACTION "
						paramindex = 2;

						(*session->callbacks.event_ctcp_action) (session, "ACTION", prefix, params, paramindex);
					}
					else
					{
						params[0] = ctcp_buf;
						paramindex = 1;

						if ( session->callbacks.event_ctcp_req )
							(*session->callbacks.event_ctcp_req) (session, "CTCP", prefix, params, paramindex);
					}
				}
				else if ( !strncasecmp (params[0], session->nick, strlen(session->nick) ) )
				{
					if ( session->callbacks.event_privmsg )
						(*session->callbacks.event_privmsg) (session, "PRIVMSG", prefix, params, paramindex);
				}
				else
				{
					if ( session->callbacks.event_channel )
						(*session->callbacks.event_channel) (session, "CHANNEL", prefix, params, paramindex);
				}
			}
		}
		else if ( !strncmp (command, "NOTICE", buf_end - command) )
		{
			size_t msglen = strlen (params[1]);

			/* 
			 * Check for CTCP request (a CTCP message starts from 0x01 
			 * and ends by 0x01
             */
			if ( paramindex > 1 && params[1][0] == 0x01 && params[1][msglen-1] == 0x01 )
			{
				char ctcp_buf[512];

				msglen -= 2;
				if ( msglen > sizeof(ctcp_buf) - 1 )
					msglen = sizeof(ctcp_buf) - 1;

				memcpy (ctcp_buf, params[1] + 1, msglen);
				ctcp_buf[msglen] = '\0';

				params[0] = ctcp_buf;
				paramindex = 1;

				if ( session->callbacks.event_ctcp_rep )
					(*session->callbacks.event_ctcp_rep) (session, "CTCP", prefix, params, paramindex);
			}
			else if ( !strncasecmp (params[0], session->nick, strlen(session->nick) ) )
			{
				if ( session->callbacks.event_notice )
					(*session->callbacks.event_notice) (session, command, prefix, params, paramindex);
			} else {
				if ( session->callbacks.event_channel_notice )
					(*session->callbacks.event_channel_notice) (session, command, prefix, params, paramindex);
			}
		}
		else if ( !strncmp (command, "INVITE", buf_end - command) )
		{
			if ( session->callbacks.event_invite )
				(*session->callbacks.event_invite) (session, command, prefix, params, paramindex);
		}
		else if ( !strncmp (command, "KILL", buf_end - command) )
		{
			; /* ignore this event - not all servers generate this */
		}
	 	else
	 	{
			/*
			 * The "unknown" event is triggered upon receipt of any number of 
			 * unclassifiable miscellaneous messages, which aren't handled by 
			 * the library.
			 */

			if ( session->callbacks.event_unknown )
				(*session->callbacks.event_unknown) (session, command, prefix, params, paramindex);
		}
	}
}


int irc_process_select_descriptors (irc_session_t * session, fd_set *in_set, fd_set *out_set)
{
	char buf[256], hname[256];

	if ( session->sock < 0 
	|| session->state == LIBIRC_STATE_INIT
	|| session->state == LIBIRC_STATE_DISCONNECTED )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		return 1;
	}

	session->lasterror = 0;
	libirc_dcc_process_descriptors (session, in_set, out_set);

	// Handle "connection succeed" / "connection failed"
	if ( session->state == LIBIRC_STATE_CONNECTING 
	&& FD_ISSET (session->sock, out_set) )
	{
		// Now we have to determine whether the socket is connected 
		// or the connect is failed
		struct sockaddr_storage saddr, laddr;
		socklen_t slen = sizeof(saddr);
		socklen_t llen = sizeof(laddr);

		if ( getsockname (session->sock, (struct sockaddr*)&laddr, &llen) < 0
		|| getpeername (session->sock, (struct sockaddr*)&saddr, &slen) < 0 )
		{
			// connection failed
			session->lasterror = LIBIRC_ERR_CONNECT;
			session->state = LIBIRC_STATE_DISCONNECTED;
			return 1;
		}

		if (saddr.ss_family == AF_INET)
			memcpy (&session->local_addr, &((struct sockaddr_in *)&laddr)->sin_addr, sizeof(struct in_addr));
		else
			memcpy (&session->local_addr, &((struct sockaddr_in6 *)&laddr)->sin6_addr, sizeof(struct in6_addr));

#if defined (ENABLE_DEBUG)
		if ( IS_DEBUG_ENABLED(session) )
			fprintf (stderr, "[DEBUG] Detected local address: %s\n", inet_ntoa(session->local_addr));
#endif

		session->state = LIBIRC_STATE_CONNECTED;

		// Get the hostname
    	if ( gethostname (hname, sizeof(hname)) < 0 )
    		strcpy (hname, "unknown");

		// Prepare the data, which should be sent to the server
		if ( session->server_password )
		{
			snprintf (buf, sizeof(buf), "PASS %s", session->server_password);
			irc_send_raw (session, buf);
		}

		snprintf (buf, sizeof(buf), "NICK %s", session->nick);
		irc_send_raw (session, buf);

		/*
		 * RFC 1459 states that "hostname and servername are normally 
         * ignored by the IRC server when the USER command comes from 
         * a directly connected client (for security reasons)", therefore 
         * we don't need them.
         */
		snprintf (buf, sizeof(buf), "USER %s unknown unknown :%s", 
				session->username ? session->username : "nobody",
				session->realname ? session->realname : "noname");
		irc_send_raw (session, buf);

		return 0;
	}

	if ( session->state != LIBIRC_STATE_CONNECTED )
		return 1;

	// Hey, we've got something to read!
	if ( FD_ISSET (session->sock, in_set) )
	{
		int offset, length = session_socket_read( session );

		if ( length < 0 )
		{
			if ( session->lasterror == 0 )
				session->lasterror = (length == 0 ? LIBIRC_ERR_CLOSED : LIBIRC_ERR_TERMINATED);
			
			session->state = LIBIRC_STATE_DISCONNECTED;
			return 1;
		}

		session->incoming_offset += length;

		// process the incoming data
		while ( (offset = libirc_findcrlf (session->incoming_buf, session->incoming_offset)) > 0 )
		{
#if defined (ENABLE_DEBUG)
			if ( IS_DEBUG_ENABLED(session) )
				libirc_dump_data ("RECV", session->incoming_buf, offset);
#endif
			// parse the string
			libirc_process_incoming_data (session, offset);

			offset = libirc_findcrlf_offset(session->incoming_buf, offset, session->incoming_offset);
			
			if ( session->incoming_offset - offset > 0 )
				memmove (session->incoming_buf, session->incoming_buf + offset, session->incoming_offset - offset);

			session->incoming_offset -= offset;
		}
	}

	// We can write a stored buffer
	if ( FD_ISSET (session->sock, out_set) )
	{
		int length;

		// Because outgoing_buf could be changed asynchronously, we should lock any change
		libirc_mutex_lock (&session->mutex_session);
		length = session_socket_write( session );

		if ( length < 0 )
		{
			if ( session->lasterror == 0 )
				session->lasterror = (length == 0 ? LIBIRC_ERR_CLOSED : LIBIRC_ERR_TERMINATED);

			session->state = LIBIRC_STATE_DISCONNECTED;

			libirc_mutex_unlock (&session->mutex_session);
			return 1;
		}

#if defined (ENABLE_DEBUG)
		if ( IS_DEBUG_ENABLED(session) )
			libirc_dump_data ("SEND", session->outgoing_buf, length);
#endif

		if ( length > 0 && session->outgoing_offset - length > 0 )
			memmove (session->outgoing_buf, session->outgoing_buf + length, session->outgoing_offset - length);

		session->outgoing_offset -= length;
		libirc_mutex_unlock (&session->mutex_session);
	}

	return 0;
}


int irc_send_raw (irc_session_t * session, const char * format, ...)
{
	char buf[1024];
	va_list va_alist;

	if ( session->state != LIBIRC_STATE_CONNECTED )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		return 1;
	}

	va_start (va_alist, format);
	vsnprintf (buf, sizeof(buf), format, va_alist);
	va_end (va_alist);

	libirc_mutex_lock (&session->mutex_session);

	if ( (strlen(buf) + 2) >= (sizeof(session->outgoing_buf) - session->outgoing_offset) )
	{
		libirc_mutex_unlock (&session->mutex_session);
		session->lasterror = LIBIRC_ERR_NOMEM;
		return 1;
	}

	strcpy (session->outgoing_buf + session->outgoing_offset, buf);
	session->outgoing_offset += strlen (buf);
	session->outgoing_buf[session->outgoing_offset++] = 0x0D;
	session->outgoing_buf[session->outgoing_offset++] = 0x0A;

	libirc_mutex_unlock (&session->mutex_session);
	return 0;
}


int irc_cmd_quit (irc_session_t * session, const char * reason)
{
	return irc_send_raw (session, "QUIT :%s", reason ? reason : "quit");
}


int irc_cmd_join (irc_session_t * session, const char * channel, const char * key)
{
	if ( !channel )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		return 1;
	}

	if ( key )
		return irc_send_raw (session, "JOIN %s :%s", channel, key);
	else
		return irc_send_raw (session, "JOIN %s", channel);
}


int irc_cmd_part (irc_session_t * session, const char * channel)
{
	if ( !channel )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		return 1;
	}

	return irc_send_raw (session, "PART %s", channel);
}


int irc_cmd_topic (irc_session_t * session, const char * channel, const char * topic)
{
	if ( !channel )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		return 1;
	}

	if ( topic )
		return irc_send_raw (session, "TOPIC %s :%s", channel, topic);
	else
		return irc_send_raw (session, "TOPIC %s", channel);
}

int irc_cmd_names (irc_session_t * session, const char * channel)
{
	if ( !channel )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		return 1;
	}

	return irc_send_raw (session, "NAMES %s", channel);
}


int irc_cmd_list (irc_session_t * session, const char * channel)
{
	if ( channel )
		return irc_send_raw (session, "LIST %s", channel);
	else
		return irc_send_raw (session, "LIST");
}


int irc_cmd_invite (irc_session_t * session, const char * nick, const char * channel)
{
	if ( !channel || !nick )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		return 1;
	}

	return irc_send_raw (session, "INVITE %s %s", nick, channel);
}


int irc_cmd_kick (irc_session_t * session, const char * nick, const char * channel, const char * comment)
{
	if ( !channel || !nick )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		return 1;
	}

	if ( comment )
		return irc_send_raw (session, "KICK %s %s :%s", channel, nick, comment);
	else
		return irc_send_raw (session, "KICK %s %s", channel, nick);
}


int irc_cmd_msg (irc_session_t * session, const char * nch, const char * text)
{
	if ( !nch || !text )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		return 1;
	}

	return irc_send_raw (session, "PRIVMSG %s :%s", nch, text);
}


int irc_cmd_notice (irc_session_t * session, const char * nch, const char * text)
{
	if ( !nch || !text )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		return 1;
	}

	return irc_send_raw (session, "NOTICE %s :%s", nch, text);
}

void irc_target_get_nick (const char * target, char *nick, size_t size)
{
	const char *p = strstr (target, "!");
	unsigned int len;

	if ( p )
		len = p - target;
	else
		len = strlen (target);

	if ( len > size-1 )
		len = size - 1;

	memcpy (nick, target, len);
	nick[len] = '\0';
}


void irc_target_get_host (const char * target, char *host, size_t size)
{
	unsigned int len;
	const char *p = strstr (target, "!");

	if ( !p )
		p = target;

	len = strlen (p);

	if ( len > size-1 )
		len = size - 1;

	memcpy (host, p, len);
	host[len] = '\0';
}


int irc_cmd_ctcp_request (irc_session_t * session, const char * nick, const char * reply)
{
	if ( !nick || !reply )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		return 1;
	}

	return irc_send_raw (session, "PRIVMSG %s :\x01%s\x01", nick, reply);
}


int irc_cmd_ctcp_reply (irc_session_t * session, const char * nick, const char * reply)
{
	if ( !nick || !reply )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		return 1;
	}

	return irc_send_raw (session, "NOTICE %s :\x01%s\x01", nick, reply);
}


void irc_get_version (unsigned int * high, unsigned int * low)
{
	*high = LIBIRC_VERSION_HIGH;
    *low = LIBIRC_VERSION_LOW;
}


void irc_set_ctx (irc_session_t * session, void * ctx)
{
	session->ctx = ctx;
}


void * irc_get_ctx (irc_session_t * session)
{
	return session->ctx;
}


void irc_disconnect (irc_session_t * session)
{
	if ( session->sock >= 0 )
		socket_close (&session->sock);

	session->sock = -1;
	session->state = LIBIRC_STATE_INIT;
}


int irc_cmd_me (irc_session_t * session, const char * nch, const char * text)
{
	if ( !nch || !text )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		return 1;
	}

	return irc_send_raw (session, "PRIVMSG %s :\x01" "ACTION %s\x01", nch, text);
}


void irc_option_set (irc_session_t * session, unsigned int option)
{
	session->options |= option;
}


void irc_option_reset (irc_session_t * session, unsigned int option)
{
	session->options &= ~option;
}


int irc_cmd_channel_mode (irc_session_t * session, const char * channel, const char * mode)
{
	if ( !channel )
	{
		session->lasterror = LIBIRC_ERR_INVAL;
		return 1;
	}

	if ( mode )
		return irc_send_raw (session, "MODE %s %s", channel, mode);
	else
		return irc_send_raw (session, "MODE %s", channel);
}


int irc_cmd_user_mode (irc_session_t * session, const char * mode)
{
	if ( mode )
		return irc_send_raw (session, "MODE %s %s", session->nick, mode);
	else
		return irc_send_raw (session, "MODE %s", session->nick);
}


int irc_cmd_nick (irc_session_t * session, const char * newnick)
{
	if ( !newnick )
	{
		session->lasterror = LIBIRC_ERR_INVAL;
		return 1;
	}

	return irc_send_raw (session, "NICK %s", newnick);
}

int irc_cmd_whois (irc_session_t * session, const char * nick)
{
	if ( !nick )
	{
		session->lasterror = LIBIRC_ERR_INVAL;
		return 1;
	}

	return irc_send_raw (session, "WHOIS %s %s", nick, nick);
}
