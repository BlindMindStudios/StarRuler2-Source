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


#ifndef INCLUDE_IRC_SESSION_H
#define INCLUDE_IRC_SESSION_H


#include "params.h"
#include "dcc.h"
#include "libirc_events.h"


// Session flags
#define SESSIONFL_MOTD_RECEIVED			(0x00000001)
#define SESSIONFL_SSL_CONNECTION		(0x00000002)
#define SESSIONFL_SSL_WRITE_WANTS_READ	(0x00000004)
#define SESSIONFL_SSL_READ_WANTS_WRITE	(0x00000008)
#define SESSIONFL_USES_IPV6				(0x00000010)



struct irc_session_s
{
	void		*	ctx;
	int				dcc_timeout;

	int				options;
	int				lasterror;

	char 			incoming_buf[LIBIRC_BUFFER_SIZE];
	unsigned int	incoming_offset;

	char 			outgoing_buf[LIBIRC_BUFFER_SIZE];
	unsigned int	outgoing_offset;
	port_mutex_t	mutex_session;

	socket_t		sock;
	int				state;
	int				flags;

	char 		  *	server;
	char		  * server_password;
	char 		  *	realname;
	char		  * username;
	char		  *	nick;

#if defined( ENABLE_IPV6 )
	struct in6_addr	local_addr6;
#endif

	struct in_addr	local_addr;
	irc_dcc_t		dcc_last_id;
	irc_dcc_session_t * dcc_sessions;
	port_mutex_t	mutex_dcc;

	irc_callbacks_t	callbacks;

#if defined (ENABLE_SSL)
	SSL 		 *	ssl;
#endif

	
};


#endif /* INCLUDE_IRC_SESSION_H */
