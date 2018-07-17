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

#ifndef INCLUDE_IRC_ERRORS_H
#define INCLUDE_IRC_ERRORS_H

#ifndef IN_INCLUDE_LIBIRC_H
	#error This file should not be included directly, include just libircclient.h
#endif


/*! brief No error
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_OK			0


/*! \brief Invalid argument
 * 
 * An invalid value was given for one of the arguments to a function. 
 * For example, supplying the NULL value for \a channel argument of 
 * irc_cmd_join() produces LIBIRC_ERR_INVAL error. You should fix the code.
 *
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_INVAL		1


/*! \brief Could not resolve host.
 * 
 * The host name supplied for irc_connect() function could not be resolved
 * into valid IP address. Usually means that host name is invalid.
 *
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_RESOLV		2


/*! \brief Could not create socket.
 * 
 * The new socket could not be created or made non-blocking. Usually means
 * that the server is out of resources, or (rarely :) a bug in libircclient.
 *
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_SOCKET		3


/*! \brief Could not connect.
 * 
 * The socket could not connect to the IRC server, or to the destination DCC
 * part. Usually means that either the IRC server is down or its address is 
 * invalid. For DCC the reason usually is the firewall on your or destination
 * computer, which refuses DCC transfer.
 *
 * \sa irc_run irc_connect
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_CONNECT		4


/*! \brief Connection closed by remote peer.
 * 
 * The IRC connection was closed by the IRC server (which could mean that an 
 * IRC operator just have banned you from the server :)), or the DCC connection
 * was closed by remote peer - for example, the other side just quits his mIrc.
 * Usually it is not an error.
 *
 * \sa irc_run irc_connect irc_dcc_callback_t
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_CLOSED		5


/*! \brief Out of memory
 * 
 * There are two possible reasons for this error. First is that memory could 
 * not be allocated for libircclient use, and this error usually is fatal.
 * Second reason is that the command queue (which keeps command ready to be 
 * sent to the IRC server) is full, and could not accept more commands yet.
 * In this case you should just wait, and repeat the command later.
 *
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_NOMEM		6


/*! \brief Could not accept new connection
 * 
 * A DCC chat/send connection from the remote peer could not be accepted.
 * Either the connection was just terminated before it is accepted, or there 
 * is a bug in libircclient.
 *
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_ACCEPT		7


/*! \brief Could not send this
 * 
 * A \a filename supplied to irc_dcc_sendfile() could not be sent. Either is 
 * is not a file (a directory or a socket, for example), or it is not readable. *
 *
 * \sa LIBIRC_ERR_OPENFILE
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_NODCCSEND	9


/*! \brief Could not read DCC file or socket
 * 
 * Either a DCC file could not be read (for example, was truncated during 
 * sending), or a DCC socket returns a read error, which usually means that
 * the network connection is terminated.
 *
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_READ			10


/*! \brief Could not write DCC file or socket
 * 
 * Either a DCC file could not be written (for example, there is no free space
 * on disk), or a DCC socket returns a write error, which usually means that
 * the network connection is terminated.
 *
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_WRITE		11


/*! \brief Invalid state
 * 
 * The function is called when it is not allowed to be called. For example,
 * irc_cmd_join() was called before the connection to IRC server succeed, and
 * ::event_connect is called.
 *
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_STATE		12


/*! \brief Operation timed out
 * 
 * The DCC request is timed out. 
 * There is a timer for each DCC request, which tracks connecting, accepting
 * and non-accepted/declined DCC requests. For every request this timer
 * is currently 60 seconds. If the DCC request was not connected, accepted
 * or declined during this time, it will be terminated with this error.
 *
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_TIMEOUT		13


/*! \brief Could not open file for DCC send
 * 
 * The file specified in irc_dcc_sendfile() could not be opened.
 *
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_OPENFILE		14


/*! \brief IRC server connection terminated
 * 
 * The connection to the IRC server was terminated - possibly, by network 
 * error. Try to irc_connect() again.
 *
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_TERMINATED	15


/*! \brief IPv6 not supported
 * 
 * The function which requires IPv6 support was called, but the IPv6 support was not compiled
 * into the application
 *
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_NOIPV6		16


/*! \brief SSL not supported
 * 
 * The SSL connection was required but the library was not compiled with SSL support
 *
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_SSL_NOT_SUPPORTED		17


/*! \brief SSL initialization failed
 * 
 * The SSL connection was required but the library was not compiled with SSL support
 *
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_SSL_INIT_FAILED			18


/*! \brief SSL connection failed
 * 
 * SSL handshare failed when attempting to connect to the server. Typically this means you're trying
 * to use SSL but attempting to connect to a non-SSL port.
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_CONNECT_SSL_FAILED		19


/*! \brief SSL certificate verify failed
 * 
 * The server is using the self-signed certificate. Use LIBIRC_OPTION_SSL_NO_VERIFY option to connect to it.
 * \ingroup errorcodes
 */
#define LIBIRC_ERR_SSL_CERT_VERIFY_FAILED	20


// Internal max error value count.
// If you added more errors, add them to errors.c too!
#define LIBIRC_ERR_MAX			21

#endif /* INCLUDE_IRC_ERRORS_H */
