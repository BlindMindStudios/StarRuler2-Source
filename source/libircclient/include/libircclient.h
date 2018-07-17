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

/*! 
 * \file libircclient.h
 * \author George Yunaev
 * \version 1.5
 * \date 01.2012
 * \brief This file defines all prototypes and functions to use libircclient.
 *
 * libircclient is a small but powerful library, which implements client-server IRC
 * protocol. It is designed to be small, fast, portable and compatible to RFC
 * standards, and most IRC clients. libircclient features include:
 * - Full multi-threading support.
 * - Single threads handles all the IRC processing.
 * - Support for single-threaded applications, and socket-based applications, 
 *   which use select()
 * - Synchronous and asynchronous interfaces.
 * - CTCP support with optional build-in reply code.
 * - Flexible DCC support, including both DCC chat, and DCC file transfer.
 * - Can both initiate and react to initiated DCC.
 * - Can accept or decline DCC sessions asynchronously.
 * - Plain C interface and implementation (possible to use from C++ code, 
 *   obviously)
 * - Compatible with RFC 1459 and most IRC clients.
 * - SSL support if compiled with --enable-openssl.
 * - Free, licensed under LGPL license.
 *
 * Note that to use libircclient, only libircclient.h should be included into your 
 * program. Do not include other libirc_* headers.
 */

#ifndef INCLUDE_LIBIRC_H
#define INCLUDE_LIBIRC_H

#include <stdlib.h>

#if !defined (WIN32)
	#include <sys/select.h>	/* fd_set */
#else
	#include <winsock2.h>
	#include <ws2tcpip.h>
	#if defined (ENABLE_IPV6)
		typedef int  (WSAAPI * getaddrinfo_ptr_t)  (const char *, const char* , const struct addrinfo *, struct addrinfo **);
		typedef void (WSAAPI * freeaddrinfo_ptr_t) (struct addrinfo*);
	#endif
#endif

#ifdef	__cplusplus
extern "C" {
#endif

/*! \brief A libircclient IRC session.
 *
 * This structure describes an IRC session. Its members are internal to 
 * libircclient, and should not be used directly.
 */
typedef struct irc_session_s	irc_session_t;

/*! \brief A libircclient DCC session.
 *
 * This structure describes a DCC session used by libircclient. 
 * Its members are internal to libircclient, and should not be used directly.
 */
typedef struct irc_dcc_session_s	irc_dcc_session_t;


/*! \brief A DCC session identifier.
 *
 * The irc_dcc_t type is a DCC session identifier, used to identify the
 * DCC sessions in callbacks and various functions.
 */
typedef unsigned int				irc_dcc_t;


/*!
 * \fn typedef void (*irc_dcc_callback_t) (irc_session_t * session, irc_dcc_t id, int status, void * ctx, const char * data, unsigned int length)
 * \brief A common DCC callback, used to inform you about the current DCC state or event.
 *
 * \param session An IRC session which generates the callback
 * \param id  A DCC session id.
 * \param status An error status. 0 means no error, otherwise error code.
 * \param ctx A user-supplied context.
 * \param data Data supplied (if available)
 * \param length data length (if available)
 *
 * This callback is called for all DCC functions when state change occurs.
 *
 * For DCC CHAT, the callback is called in next circumstances:
 * - \a status is LIBIRC_ERR_CLOSED: connection is closed by remote peer. 
 *      After returning from the callback, the DCC session is automatically 
 *      destroyed.
 * - \a status is neither 0 nor LIBIRC_ERR_CLOSED: socket I/O error 
 *      (connect error, accept error, recv error, send error). After returning 
 *      from the callback, the DCC session is automatically destroyed.
 * - \a status is 0: new chat message received, \a data contains the message
 *      (null-terminated string), \a length contains the message length.
 *      
 * For DCC SEND, while file is sending, callback called in next circumstances:
 * - \a status is neither 0 nor LIBIRC_ERR_CLOSED: socket I/O error 
 *      (connect error, accept error, recv error, send error). After returning 
 *      from the callback, the DCC session is automatically destroyed.
 * - \a status is 0: new data received, \a data contains the data received,
 *      \a length contains the amount of data received.
 *      
 * For DCC RECV, while file is sending, callback called in next circumstances:
 * - \a status is neither 0 nor LIBIRC_ERR_CLOSED: socket I/O error 
 *      (connect error, accept error, recv error, send error). After returning 
 *      from the callback, the DCC session is automatically destroyed.
 * - \a status is 0, and \a data is 0: file has been received successfully.
 *      After returning from the callback, the DCC session is automatically 
 *      destroyed.
 * - \a status is 0, and \a data is not 0: new data received, \a data contains 
 *      the data received, \a length contains the amount of data received.
 *
 * \ingroup dccstuff
 */
typedef void (*irc_dcc_callback_t) (irc_session_t * session, irc_dcc_t id, int status, void * ctx, const char * data, unsigned int length);


#define IN_INCLUDE_LIBIRC_H
#include "libirc_errors.h"
#include "libirc_events.h"
#include "libirc_options.h"
#undef IN_INCLUDE_LIBIRC_H


/*!
 * \fn irc_session_t * irc_create_session (irc_callbacks_t * callbacks)
 * \brief Creates and initiates a new IRC session.
 *
 * \param callbacks A structure, which defines several callbacks, which will 
 *                  be called on appropriate events. Must not be NULL.
 *
 * \return An ::irc_session_t object, or 0 if creation failed. Usually,
 *         failure is caused by out of memory error.
 *
 * Every ::irc_session_t object describes a single IRC session - a connection
 * to an IRC server, and possibly to some DCC clients. Almost every irc_* 
 * function requires this object to be passed to, and therefore this function 
 * should be called first.
 *
 * Every session created must be destroyed when it is not needed anymore
 * by calling irc_destroy_session().
 *
 * The most common function sequence is:
 * \code
 *  ... prepare irc_callbacks_t structure ...
 *  irc_create_session();
 *  irc_connect();
 *  irc_run();
 *  irc_destroy_session();
 * \endcode
 *
 * \sa irc_destroy_session
 * \ingroup initclose
 */
irc_session_t * irc_create_session (irc_callbacks_t	* callbacks);


/*!
 * \fn void irc_destroy_session (irc_session_t * session)
 * \brief Destroys previously created IRC session.
 *
 * \param session A session to destroy. Must not be NULL.
 *
 * This function should be used to destroy an IRC session, close the 
 * connection to the IRC server, and free all the used resources. After 
 * calling this function, you should not use this session object anymore.
 *
 * \ingroup initclose
 */
void irc_destroy_session (irc_session_t * session);


/*!
 * \fn int irc_connect (irc_session_t * session, const char * server, unsigned short port, const char * server_password, const char * nick, const char * username, const char * realname);
 * \brief Initiates a connection to IRC server.
 *
 * \param session A session to initiate connections on. Must not be NULL.
 * \param server  A domain name or an IP address of the IRC server to connect to. Cannot be NULL.
 *                If the library is built with SSL support and the first character is hash, tries to establish the SSL connection. 
 *                For example, the connection to "irc.example.com" is assumed to be plaintext, and connection to "#irc.example.com"
 *                is assumed to be secured by SSL. Note that SSL will only work if the library is built with the SSL support.
 * \param port    An IRC server port, usually 6667.
 * \param server_password  An IRC server password, if the server requires it.
 *                May be NULL, in this case password will not be send to the 
 *                IRC server. Vast majority of IRC servers do not require passwords.
 * \param nick    A nick, which libircclient will use to login to the IRC server.
 *                Must not be NULL.
 * \param username A username of the account, which is used to connect to the
 *                IRC server. This is for information only, will be shown in
 *                "user properties" dialogs and returned by /whois request.
 *                May be NULL, in this case 'nobody' will be sent as username.
 * \param realname A real name of the person, who connects to the IRC. Usually
 *                people put some wide-available information here (URL, small
 *                description or something else). This information also will 
 *                be shown in "user properties" dialogs and returned by /whois 
 *                request. May be NULL, in this case 'noname' will be sent as 
 *                username.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * This function prepares and initiates a connection to the IRC server. The
 * connection is done asynchronously (see irc_callbacks_t::event_connect), so the success 
 * return value means that connection was initiated (but not completed!)
 * successfully.
 *
 * \sa irc_run
 * \ingroup conndisc
 */
int irc_connect (irc_session_t * session, 
			const char * server, 
			unsigned short port,
			const char * server_password,
			const char * nick,
			const char * username,
			const char * realname);


/*!
 * \fn int irc_connect6 (irc_session_t * session, const char * server, unsigned short port, const char * server_password, const char * nick, const char * username, const char * realname);
 * \brief Initiates a connection to IRC server using IPv6.
 *
 * \param session A session to initiate connections on. Must not be NULL.
 * \param server  A domain name or an IP address of the IRC server to connect to. Cannot be NULL.
 *                If the library is built with SSL support and the first character is hash, tries to establish the SSL connection. 
 *                For example, the connection to "irc.example.com" is assumed to be plaintext, and connection to "#irc.example.com"
 *                is assumed to be secured by SSL. Note that SSL will only work if the library is built with the SSL support.
 * \param port    An IRC server port, usually 6667. 
 * \param server_password  An IRC server password, if the server requires it.
 *                May be NULL, in this case password will not be send to the 
 *                IRC server. Vast majority of IRC servers do not require passwords.
 * \param nick    A nick, which libircclient will use to login to the IRC server.
 *                Must not be NULL.
 * \param username A username of the account, which is used to connect to the
 *                IRC server. This is for information only, will be shown in
 *                "user properties" dialogs and returned by /whois request.
 *                May be NULL, in this case 'nobody' will be sent as username.
 * \param realname A real name of the person, who connects to the IRC. Usually
 *                people put some wide-available information here (URL, small
 *                description or something else). This information also will 
 *                be shown in "user properties" dialogs and returned by /whois 
 *                request. May be NULL, in this case 'noname' will be sent as 
 *                username.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * This function prepares and initiates a connection to the IRC server. The
 * connection is done asynchronously (see irc_callbacks_t::event_connect), so the success 
 * return value means that connection was initiated (but not completed!)
 * successfully.
 *
 * \sa irc_run
 * \ingroup conndisc
 */
int irc_connect6 (irc_session_t * session, 
			const char * server, 
			unsigned short port,
			const char * server_password,
			const char * nick,
			const char * username,
			const char * realname);

/*!
 * \fn void irc_disconnect (irc_session_t * session)
 * \brief Disconnects a connection to IRC server.
 *
 * \param session An IRC session.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno().
 *
 * This function closes the IRC connection. After that connection is closed,
 * libircclient automatically leaves irc_run loop.
 *
 * \sa irc_connect irc_run
 * \ingroup conndisc
 */
void irc_disconnect (irc_session_t * session);


/*!
 * \fn int irc_is_connected (irc_session_t * session)
 * \brief Checks whether the session is connecting/connected to the IRC server.
 *
 * \param session An initialized IRC session.
 *
 * \return Return code 1 means that session is connecting or connected to the
 *   IRC server, zero value means that the session has been disconnected.
 *
 * \sa irc_connect irc_run
 * \ingroup conndisc
 */
int irc_is_connected (irc_session_t * session);


/*!
 * \fn int irc_run (irc_session_t * session)
 * \brief Goes into forever-loop, processing IRC events and generating 
 *  callbacks.
 *
 * \param session An initiated and connected session.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno().
 *
 * This function goes into forever loop, processing the IRC events, and 
 * calling appropriate callbacks. This function will not return until the 
 * server connection is terminated - either by server, or by calling 
 * irc_cmd_quit. This function should be used, if you don't need asynchronous
 * request processing (i.e. your bot just reacts on the events, and doesn't
 * generate it asynchronously). Even in last case, you still can call irc_run,
 * and start the asynchronous thread in event_connect handler. See examples. 
 *
 * \ingroup running 
 */
int irc_run (irc_session_t * session);


/*!
 * \fn int irc_add_select_descriptors (irc_session_t * session, fd_set *in_set, fd_set *out_set, int * maxfd)
 * \brief Adds IRC socket(s) for the descriptor set to use in select().
 *
 * \param session An initiated and connected session.
 * \param in_set  A FD_IN descriptor set for select()
 * \param out_set A FD_OUT descriptor set for select()
 * \param maxfd   A max descriptor found.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno().
 *
 * This function should be used when you already have a program with select()
 * based data processing. You prepare your descriptors, call this function
 * to add session's descriptor(s) into set, and then call select(). When it
 * returns, you should call irc_add_select_descriptors, which sends/recvs all
 * available data, parses received data, calls your callbacks(!), and returns.
 * Then you can process your sockets from set. See the example.
 *
 * \sa irc_process_select_descriptors
 * \ingroup running 
 */
int irc_add_select_descriptors (irc_session_t * session, fd_set *in_set, fd_set *out_set, int * maxfd);


/*!
 * \fn int irc_process_select_descriptors (irc_session_t * session, fd_set *in_set, fd_set *out_set)
 * \brief Processes the IRC socket(s), which descriptor(s) are set.
 *
 * \param session An initiated and connected session.
 * \param in_set  A FD_IN descriptor set for select()
 * \param out_set A FD_OUT descriptor set for select()
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno().
 *
 * This function should be used in pair with irc_add_select_descriptors 
 * function. See irc_add_select_descriptors description.
 *
 * \sa irc_add_select_descriptors
 * \ingroup running 
 */
int irc_process_select_descriptors (irc_session_t * session, fd_set *in_set, fd_set *out_set);


/*!
 * \fn int irc_send_raw (irc_session_t * session, const char * format, ...)
 * \brief Sends raw data to the IRC server.
 *
 * \param session An initiated and connected session.
 * \param format  A printf-formatted string, followed by function args.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * This function sends the raw data as-is to the IRC server. Use it to 
 * generate a server command, which is not (yet) provided by libircclient 
 * directly.
 *
 * \ingroup ircmd_oth
 */
int irc_send_raw (irc_session_t * session, const char * format, ...);


/*!
 * \fn int irc_cmd_quit (irc_session_t * session, const char * reason)
 * \brief Sends QUIT command to the IRC server.
 *
 * \param session An initiated and connected session.
 * \param reason  A reason to quit. May be NULL.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * This function sends the QUIT command to the IRC server. This command 
 * forces the IRC server to close the IRC connection, and terminate the 
 * session.
 *
 * \ingroup ircmd_oth
 */
int irc_cmd_quit (irc_session_t * session, const char * reason);


/*!
 * \fn int irc_cmd_join (irc_session_t * session, const char * channel, const char * key)
 * \brief Joins the new IRC channel.
 *
 * \param session An initiated and connected session.
 * \param channel A channel name to join to. Must not be NULL.
 * \param key     Channel password. May be NULL.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * This function is used to JOIN the IRC channel. If the channel is not exist,
 * it will be automatically created by the IRC server. Note that to JOIN the
 * password-protected channel, you must know the password, and specify it in
 * the \a key argument.
 *
 * If join is successful, the irc_callbacks_t::event_join is called (with \a origin == 
 * your nickname), then you are sent the channel's topic 
 * (using ::LIBIRC_RFC_RPL_TOPIC) and the list of users who are on the 
 * channel (using ::LIBIRC_RFC_RPL_NAMREPLY), which includes the user 
 * joining - namely you.
 *
 * Possible error responces for this command from the RFC1459:
 * - ::LIBIRC_RFC_ERR_NEEDMOREPARAMS
 * - ::LIBIRC_RFC_ERR_BANNEDFROMCHAN
 * - ::LIBIRC_RFC_ERR_INVITEONLYCHAN
 * - ::LIBIRC_RFC_ERR_BADCHANNELKEY
 * - ::LIBIRC_RFC_ERR_CHANNELISFULL
 * - ::LIBIRC_RFC_ERR_BADCHANMASK
 * - ::LIBIRC_RFC_ERR_NOSUCHCHANNEL
 * - ::LIBIRC_RFC_ERR_TOOMANYCHANNELS
 *
 * And on success the following replies returned:
 * - ::LIBIRC_RFC_RPL_TOPIC
 * - ::LIBIRC_RFC_RPL_NAMREPLY
 * 
 * \ingroup ircmd_ch
 */
int irc_cmd_join (irc_session_t * session, const char * channel, const char * key);


/*!
 * \fn int irc_cmd_part (irc_session_t * session, const char * channel)
 * \brief Leaves the IRC channel.
 *
 * \param session An initiated and connected session.
 * \param channel A channel name to leave. Must not be NULL.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * This function is used to leave the IRC channel you've already joined to.
 * An attempt to leave the channel you aren't in results a ::LIBIRC_RFC_ERR_NOTONCHANNEL
 * server error.
 *
 * Possible error responces for this command from the RFC1459:
 * - ::LIBIRC_RFC_ERR_NEEDMOREPARAMS
 * - ::LIBIRC_RFC_ERR_NOSUCHCHANNEL
 * - ::LIBIRC_RFC_ERR_NOTONCHANNEL
 *
 * \ingroup ircmd_ch
 */
int irc_cmd_part (irc_session_t * session, const char * channel);


/*!
 * \fn int irc_cmd_invite (irc_session_t * session, const char * nick, const char * channel)
 * \brief Invites a user to invite-only channel.
 *
 * \param session An initiated and connected session.
 * \param nick    A nick to invite. Must not be NULL.
 * \param channel A channel name to invite to. Must not be NULL.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * This function is used to invite someone to invite-only channel. 
 * "Invite-only" is a channel mode, which restricts anyone, except invided,
 * to join this channel. After invitation, the user could join this channel.
 * The user, who is invited, will receive the irc_callbacks_t::event_invite event.
 * Note that you must be a channel operator to INVITE the users.
 *
 * Possible error responces for this command from the RFC1459:
 * - ::LIBIRC_RFC_ERR_NEEDMOREPARAMS
 * - ::LIBIRC_RFC_ERR_NOSUCHNICK
 * - ::LIBIRC_RFC_ERR_NOTONCHANNEL
 * - ::LIBIRC_RFC_ERR_ERR_USERONCHANNEL
 * - ::LIBIRC_RFC_ERR_ERR_CHANOPRIVSNEEDED
 *
 * And on success one of the following replies returned:
 * - ::LIBIRC_RFC_RPL_INVITING
 * - ::LIBIRC_RFC_RPL_AWAY
 *
 * \sa irc_callbacks_t::event_invite irc_cmd_channel_mode
 * \ingroup ircmd_ch
 */
int irc_cmd_invite (irc_session_t * session, const char * nick, const char * channel);


/*!
 * \fn int irc_cmd_names (irc_session_t * session, const char * channel)
 * \brief Obtains a list of users who're in channel.
 *
 * \param session An initiated and connected session.
 * \param channel A channel name(s) to obtain user list. Must not be NULL. 
 *                It is possible to specify more than a single channel, but 
 *                several channel names should be separated by a comma.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * This function is used to ask the IRC server for the list of the users 
 * who're in specified channel. You can list all nicknames that are visible 
 * to you on any channel that you can see. The list of users will be returned 
 * using ::RPL_NAMREPLY and ::RPL_ENDOFNAMES numeric codes.
 *
 * The channel names are returned by irc_callbacks_t::event_numeric 
 * using the following reply codes:
 * - ::LIBIRC_RFC_RPL_NAMREPLY
 * - ::LIBIRC_RFC_RPL_ENDOFNAMES
 *
 * \ingroup ircmd_ch
 */
int irc_cmd_names (irc_session_t * session, const char * channel);


/*!
 * \fn int irc_cmd_list (irc_session_t * session, const char * channel)
 * \brief Obtains a list of active server channels with their topics.
 *
 * \param session An initiated and connected session.
 * \param channel A channel name(s) to list. May be NULL, in which case all the
 *                channels will be listed. It is possible to specify more than 
 *                a single channel, but several channel names should be 
 *                separated by a comma.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * This function is used to ask the IRC server for the active (existing) 
 * channels list. The list will be returned using ::LIBIRC_RFC_RPL_LISTSTART - 
 * ::LIBIRC_RFC_RPL_LIST - ::LIBIRC_RFC_RPL_LISTEND sequence.
 * Note that "private" channels are listed (without their topics) as channel 
 * "Prv" unless the client generating the LIST query is actually on that 
 * channel. Likewise, secret channels are 
 * not listed at all unless the client is a member of the channel in question.
 *
 * Possible error responces for this command from the RFC1459:
 * - ::LIBIRC_RFC_ERR_NOSUCHSERVER
 *
 * And the channel list is returned using the following reply codes:
 * - ::LIBIRC_RFC_RPL_LISTSTART
 * - ::LIBIRC_RFC_RPL_LISTEND
 * - ::LIBIRC_RFC_RPL_LIST
 *
 * \ingroup ircmd_ch
 */
int irc_cmd_list (irc_session_t * session, const char * channel);


/*!
 * \fn int irc_cmd_topic (irc_session_t * session, const char * channel, const char * topic)
 * \brief Views or changes the channel topic.
 *
 * \param session An initiated and connected session.
 * \param channel A channel name to invite to. Must not be NULL.
 * \param topic   A new topic to change. If NULL, the old topic will be 
 *                returned, and topic won't changed.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * The irc_cmd_topic() is used to change or view the topic of a channel.
 * The topic for \a channel is returned if \a topic is NULL. If the \a topic
 * is not NULL, the topic for the \a channel will be changed. Note that, 
 * depending on \a +t channel mode, you may be required to be a channel 
 * operator to change the channel topic.
 *
 * If the command succeed, the IRC server will generate a ::RPL_NOTOPIC or 
 * ::RPL_TOPIC message, containing either old or changed topic. Also the IRC
 * server can (but not have to) generate the non-RFC ::RPL_TOPIC_EXTRA message,
 * containing the nick of person, who's changed the topic, and the time of 
 * latest topic change.
 *
 * Possible error responces for this command from the RFC1459:
 * - ::LIBIRC_RFC_ERR_NEEDMOREPARAMS
 * - ::LIBIRC_RFC_ERR_CHANOPRIVSNEEDED
 * - ::LIBIRC_RFC_ERR_NOTONCHANNEL
 *
 * And the topic information is returned using one of following reply codes:
 * - ::LIBIRC_RFC_RPL_NOTOPIC
 * - ::LIBIRC_RFC_RPL_TOPIC
 *
 * \sa irc_callbacks_t::event_topic irc_cmd_channel_mode
 * \ingroup ircmd_ch
 */
int irc_cmd_topic (irc_session_t * session, const char * channel, const char * topic);


/*!
 * \fn int irc_cmd_channel_mode (irc_session_t * session, const char * channel, const char * mode)
 * \brief Views or changes the channel mode.
 *
 * \param session An initiated and connected session.
 * \param channel A channel name to invite to. Must not be NULL.
 * \param mode    A channel mode, described below. If NULL, the channel mode is
 *                not changed, just the old mode is returned.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * The irc_cmd_channel_mode() is used to change or view the channel modes.
 * The \a channel mode is returned if the \a mode is NULL. If the \a mode
 * is not NULL, the mode for the \a channel will be changed. Note that, 
 * only channel operators can change the channel modes.
 *
 * Channel mode is represended by the letters combination. Every letter has
 * its own meaning in channel modes. Most channel mode letters are boolean
 * (i.e. could only be set or reset), but a few channel mode letters accept a 
 * parameter. All channel options are set by adding a plus sign before the 
 * letter, and reset by adding a minus sign before the letter.
 * 
 * Here is the list of 'standard' channel modes:
 *
 * - \a o \a nickname - gives (+o nick) or takes (-o nick) the channel 
 *      operator privileges from  a \a nickname. This mode affects the 
 *      users in channel, not the channel itself. 
 *      Examples: "+o tim", "-o watson".
 *
 * - \a p - sets (+p) or resets (-p) private channel flag. 
 *      Private channels are shown in channel list as 'Prv', without the topic.
 *
 * - \a s - sets (+p) or resets (-p) secret channel flag. 
 *      Secret channels aren't shown in channel list at all.
 *
 * - \a i - sets (+i) or resets (-i) invite-only channel flag. When the flag
 *      is set, only the people who are invited by irc_cmd_invite(), can
 *      join this channel.
 *
 * - \a t - sets (+t) or resets (-t) topic settable by channel operator only
 *      flag. When the flag is set, only the channel operators can change the
 *      channel topic.
 *
 * - \a n - sets (+n) or resets (-n) the protection from the clients outside 
 *      the channel. When the \a +n mode is set, only the clients, who are in 
 *      channel, can send the messages to the channel.
 *
 * - \a m - sets (+m) or resets (-m) the moderation of the channel. When the
 *      moderation mode is set, only channel operators and the users who have
 *      the \a +v user mode can speak in the channel.
 *
 * - \a v \a nickname - gives (+v nick) or takes (-v nick) from user the 
 *      ability to speak on a moderated channel.
 *      Examples: "+v tim", "-v watson".
 *
 * - \a l \a number - sets (+l 20) or removes (-l) the restriction of maximum
 *      users in channel. When the restriction is set, and there is a number
 *      of users in the channel, no one can join the channel anymore.
 *
 * - \a k \a key - sets (+k secret) or removes (-k) the password from the 
 *      channel. When the restriction is set, any user joining the channel 
 *      required to provide a channel key.
 *
 * - \a b \a mask - sets (+b *!*@*.mil) or removes (-b *!*@*.mil) the ban mask
 *      on a user to keep him out of channel. Note that to remove the ban you 
 *      must specify the ban mask to remove, not just "-b".
 *
 * Note that the actual list of channel modes depends on the IRC server, and
 * can be bigger. If you know the popular channel modes, which aren't 
 * mentioned here - please contact me at tim@krasnogorsk.ru
 *
 * Possible error responces for this command from the RFC1459:
 * - ::LIBIRC_RFC_ERR_NEEDMOREPARAMS
 * - ::LIBIRC_RFC_ERR_CHANOPRIVSNEEDED
 * - ::LIBIRC_RFC_ERR_NOSUCHNICK
 * - ::LIBIRC_RFC_ERR_NOTONCHANNEL
 * - ::LIBIRC_RFC_ERR_KEYSET
 * - ::LIBIRC_RFC_ERR_UNKNOWNMODE
 * - ::LIBIRC_RFC_ERR_NOSUCHCHANNEL
 *
 * And the mode information is given using following reply codes:
 * - ::LIBIRC_RFC_RPL_CHANNELMODEIS
 * - ::LIBIRC_RFC_RPL_BANLIST
 * - ::LIBIRC_RFC_RPL_ENDOFBANLIST
 *
 * \sa irc_cmd_topic irc_cmd_list
 * \ingroup ircmd_ch
 */
int irc_cmd_channel_mode (irc_session_t * session, const char * channel, const char * mode);


/*!
 * \fn int irc_cmd_user_mode (irc_session_t * session, const char * mode)
 * \brief Views or changes your own user mode.
 *
 * \param session An initiated and connected session.
 * \param mode    A user mode, described below. If NULL, the user mode is
 *                not changed, just the old mode is returned.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * The irc_cmd_user_mode() is used to change or view the user modes.
 * Note that, unlike channel modes, not all user modes can be changed. 
 * The user mode is returned if the \a mode is NULL. If the \a mode
 * is not NULL, the mode for you will be changed, and new mode will be 
 * returned.
 *
 * Like channel mode, user mode is also represended by the letters combination.
 * All the user mode letters are boolean (i.e. could only be set or reset),
 * they are set by adding a plus sign before the letter, and reset by adding 
 * a minus sign before the letter.
 * 
 * Here is the list of 'standard' user modes:
 *
 * - \a o - represents an IRC operator status. Could not be set directly (but
 *      can be reset though), to set it use the IRC \a OPER command.
 *
 * - \a i - if set, marks a user as 'invisible' - that is, not seen by lookups 
 *      if the user is not in a channel.
 *
 * - \a w - if set, marks a user as 'receiving wallops' - special messages 
 *      generated by IRC operators using WALLOPS command.
 *
 * - \a s - if set, marks a user for receipt of server notices.
 *
 * - \a r - NON-STANDARD MODE. If set, user has been authenticated with 
 *      NICKSERV IRC service.
 *
 * - \a x - NON-STANDARD MODE. If set, user's real IP is hidden by IRC 
 *      servers, to prevent scriptkiddies to do nasty things to the user's 
 *      computer.
 *
 * Note that the actual list of user modes depends on the IRC server, and
 * can be bigger. If you know the popular user modes, which aren't 
 * mentioned here - please contact me at tim@krasnogorsk.ru
 *
 * Possible error responces for this command from the RFC1459:
 * - ::LIBIRC_RFC_ERR_NEEDMOREPARAMS
 * - ::LIBIRC_RFC_ERR_NOSUCHNICK
 * - ::LIBIRC_RFC_ERR_UNKNOWNMODE
 * - ::LIBIRC_RFC_ERR_USERSDONTMATCH
 * - ::LIBIRC_RFC_ERR_UMODEUNKNOWNFLAG
 *
 * And the mode information is given using reply code ::LIBIRC_RFC_RPL_UMODEIS
 *
 * \ingroup ircmd_oth
 */
int irc_cmd_user_mode (irc_session_t * session, const char * mode);


/*!
 * \fn int irc_cmd_nick (irc_session_t * session, const char * newnick)
 * \brief Changes your nick.
 *
 * \param session An initiated and connected session.
 * \param newnick A new nick. Must not be NULL.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * This function is used to change your current nick to another nick. Note 
 * that such a change is not always possible; for example you cannot change 
 * nick to the existing nick, or (on some servers) to the registered nick.
 *
 * Possible error responces for this command from the RFC1459:
 * - ::LIBIRC_RFC_ERR_NONICKNAMEGIVEN
 * - ::LIBIRC_RFC_ERR_ERRONEUSNICKNAME
 * - ::LIBIRC_RFC_ERR_NICKNAMEINUSE
 * - ::LIBIRC_RFC_ERR_NICKCOLLISION
 *
 * \ingroup ircmd_oth
 */
int irc_cmd_nick (irc_session_t * session, const char * newnick);


/*!
 * \fn int irc_cmd_whois (irc_session_t * session, const char * nick)
 * \brief Queries the information about the nick.
 *
 * \param session An initiated and connected session.
 * \param nick    A nick to query the information abour. Must not be NULL. 
 *                A comma-separated list of several nicknames may be given.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * This function queries various information about the nick: username, real 
 * name, the IRC server used, the channels user is in, idle time, away mode and so on.
 *
 * Possible error responces for this command from the RFC1459:
 * - ::LIBIRC_RFC_ERR_NOSUCHSERVER
 * - ::LIBIRC_RFC_ERR_NOSUCHNICK
 * - ::LIBIRC_RFC_ERR_NONICKNAMEGIVEN
 *
 * And the information is returned using the following reply codes. The whois
 * query is completed when ::LIBIRC_RFC_RPL_ENDOFWHOIS message is received.
 * - ::LIBIRC_RFC_RPL_WHOISUSER
 * - ::LIBIRC_RFC_RPL_WHOISCHANNELS
 * - ::LIBIRC_RFC_RPL_WHOISSERVER
 * - ::LIBIRC_RFC_RPL_AWAY
 * - ::LIBIRC_RFC_RPL_WHOISOPERATOR
 * - ::LIBIRC_RFC_RPL_WHOISIDLE
 * - ::LIBIRC_RFC_RPL_ENDOFWHOIS
 *
 * \ingroup ircmd_oth
 */
int irc_cmd_whois (irc_session_t * session, const char * nick);


/*!
 * \fn irc_cmd_msg  (irc_session_t * session, const char * nch, const char * text)
 * \brief Sends the message to the nick or to the channel.
 *
 * \param session An initiated and connected session.
 * \param nch     A target nick or channel. Must not be NULL.
 * \param text    Message text. Must not be NULL.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * This function is used to send the channel or private messages. The target
 * is determined by \a nch argument: if it describes nick, this will be a 
 * private message, if a channel name - public (channel) message. Note that
 * depending on channel modes, you may be required to join the channel to
 * send the channel messages.
 *
 * Possible error responces for this command from the RFC1459:
 * - ::LIBIRC_RFC_ERR_NORECIPIENT
 * - ::LIBIRC_RFC_ERR_NOTEXTTOSEND
 * - ::LIBIRC_RFC_ERR_CANNOTSENDTOCHAN
 * - ::LIBIRC_RFC_ERR_NOTONCHANNEL
 * - ::LIBIRC_RFC_ERR_NOTOPLEVEL
 * - ::LIBIRC_RFC_ERR_WILDTOPLEVEL
 * - ::LIBIRC_RFC_ERR_TOOMANYTARGETS
 * - ::LIBIRC_RFC_ERR_NOSUCHNICK
 *
 * On success there is NOTHING generated.
 *
 * \ingroup ircmd_msg
 */
int irc_cmd_msg  (irc_session_t * session, const char * nch, const char * text);


/*!
 * \fn int irc_cmd_me	 (irc_session_t * session, const char * nch, const char * text)
 * \brief Sends the /me (CTCP ACTION) message to the nick or to the channel.
 *
 * \param session An initiated and connected session.
 * \param nch     A target nick or channel. Must not be NULL.
 * \param text    Action message text. Must not be NULL.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * This function is used to send the /me message to channel or private.
 * As for irc_cmd_msg, the target is determined by \a nch argument.
 *
 * Possible error responces for this command from the RFC1459:
 * - ::LIBIRC_RFC_ERR_NORECIPIENT
 * - ::LIBIRC_RFC_ERR_NOTEXTTOSEND
 * - ::LIBIRC_RFC_ERR_CANNOTSENDTOCHAN
 * - ::LIBIRC_RFC_ERR_NOTONCHANNEL
 * - ::LIBIRC_RFC_ERR_NOTOPLEVEL
 * - ::LIBIRC_RFC_ERR_WILDTOPLEVEL
 * - ::LIBIRC_RFC_ERR_TOOMANYTARGETS
 * - ::LIBIRC_RFC_ERR_NOSUCHNICK
 *
 * On success there is NOTHING generated. 
 * However, a ::LIBIRC_RFC_RPL_AWAY reply can be also generated.            
 *
 * \sa irc_cmd_msg
 * \ingroup ircmd_msg
 */
int irc_cmd_me (irc_session_t * session, const char * nch, const char * text);


/*!
 * \fn int irc_cmd_notice (irc_session_t * session, const char * nch, const char * text)
 * \brief Sends the notice to the nick or to the channel.
 *
 * \param session An initiated and connected session.
 * \param nch     A target nick or channel. Must not be NULL.
 * \param text    Notice text. Must not be NULL.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * This function is used to send the channel or private notices. The target
 * is determined by \a nch argument: if it describes nick, this will be a 
 * private message, if a channel name - public (channel) message. Note that
 * depending on channel modes, you may be required to join the channel to
 * send the channel notices.
 *
 * The only difference between message and notice is that, according to RFC 
 * 1459, you must not automatically reply to NOTICE messages.
 *
 * Possible error responces for this command from the RFC1459:
 * - ::LIBIRC_RFC_ERR_NORECIPIENT
 * - ::LIBIRC_RFC_ERR_NOTEXTTOSEND
 * - ::LIBIRC_RFC_ERR_CANNOTSENDTOCHAN
 * - ::LIBIRC_RFC_ERR_NOTONCHANNEL
 * - ::LIBIRC_RFC_ERR_NOTOPLEVEL
 * - ::LIBIRC_RFC_ERR_WILDTOPLEVEL
 * - ::LIBIRC_RFC_ERR_TOOMANYTARGETS
 * - ::LIBIRC_RFC_ERR_NOSUCHNICK
 *
 * On success there is NOTHING generated. On notices sent to target nick, 
 * a ::LIBIRC_RFC_RPL_AWAY reply may be generated.
 *
 * \sa irc_cmd_msg
 * \ingroup ircmd_msg
 */
int irc_cmd_notice (irc_session_t * session, const char * nch, const char * text);


/*!
 * \fn int irc_cmd_kick (irc_session_t * session, const char * nick, const char * channel, const char * reason)
 * \brief Kick some lazy ass out of channel.
 *
 * \param session An initiated and connected session.
 * \param nick    A nick to kick. Must not be NULL.
 * \param channel A channel to kick this nick out of. Must not be NULL.
 * \param reason  A reason to kick. May be NULL.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * This function is used to kick a person out of channel. Note that you must
 * be a channel operator to kick anyone.
 *
 * Possible error responces for this command from the RFC1459:
 * - ::LIBIRC_RFC_ERR_NEEDMOREPARAMS
 * - ::LIBIRC_RFC_ERR_BADCHANMASK
 * - ::LIBIRC_RFC_ERR_NOSUCHCHANNEL
 * - ::LIBIRC_RFC_ERR_NOTONCHANNEL
 * - ::LIBIRC_RFC_ERR_CHANOPRIVSNEEDED
 *
 * On success the irc_callbacks_t::event_kick event will be generated.
 *
 * \sa irc_callbacks_t::event_numeric
 * \ingroup ircmd_ch
 */
int irc_cmd_kick (irc_session_t * session, const char * nick, const char * channel, const char * reason);


/*!
 * \fn int irc_cmd_ctcp_request (irc_session_t * session, const char * nick, const char * request)
 * \brief Generates a CTCP request.
 *
 * \param session An initiated and connected session.
 * \param nick    A target nick to send request to. Must not be NULL.
 * \param request A request string. Must not be NULL.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * This function is used to send a CTCP request. There are four CTCP requests
 * supported by Mirc:
 *  VERSION - get the client software name and version
 *  FINGER  - get the client username, host and real name.
 *  PING    - get the client delay.
 *  TIME    - get the client local time.
 *
 * A reply to the CTCP request will be sent by the irc_callbacks_t::event_ctcp_rep callback;
 * be sure to define it.
 *
 * Possible error responces for this command from the RFC1459:
 * - ::LIBIRC_RFC_ERR_NORECIPIENT
 * - ::LIBIRC_RFC_ERR_NOTEXTTOSEND
 * - ::LIBIRC_RFC_ERR_CANNOTSENDTOCHAN
 * - ::LIBIRC_RFC_ERR_NOTONCHANNEL
 * - ::LIBIRC_RFC_ERR_NOTOPLEVEL
 * - ::LIBIRC_RFC_ERR_WILDTOPLEVEL
 * - ::LIBIRC_RFC_ERR_TOOMANYTARGETS
 * - ::LIBIRC_RFC_ERR_NOSUCHNICK
 *
 * \sa irc_callbacks_t::event_ctcp_rep irc_callbacks_t::event_numeric
 * \ingroup ctcp
 */
int irc_cmd_ctcp_request (irc_session_t * session, const char * nick, const char * request);


/*!
 * \fn int irc_cmd_ctcp_reply (irc_session_t * session, const char * nick, const char * reply)
 * \brief Generates a reply to the CTCP request.
 *
 * \param session An initiated and connected session.
 * \param nick    A target nick to send request to. Must not be NULL.
 * \param reply   A reply string. Must not be NULL.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * This function is used to send a reply to the CTCP request, generated by 
 * irc_callbacks_t::event_ctcp_req. Note that you will not receive this event
 * unless you specify your own handler as \c event_ctcp_req callback during
 * the IRC session initialization.
 *
 * Possible error responces for this command from the RFC1459:
 * - ::LIBIRC_RFC_ERR_NORECIPIENT
 * - ::LIBIRC_RFC_ERR_NOTEXTTOSEND
 * - ::LIBIRC_RFC_ERR_CANNOTSENDTOCHAN
 * - ::LIBIRC_RFC_ERR_NOTONCHANNEL
 * - ::LIBIRC_RFC_ERR_NOTOPLEVEL
 * - ::LIBIRC_RFC_ERR_WILDTOPLEVEL
 * - ::LIBIRC_RFC_ERR_TOOMANYTARGETS
 * - ::LIBIRC_RFC_ERR_NOSUCHNICK
 *
 * \ingroup ctcp
 */
int irc_cmd_ctcp_reply (irc_session_t * session, const char * nick, const char * reply);


/*!
 * \fn void irc_target_get_nick (const char * target, char *nick, size_t size)
 * \brief Gets the nick part from the target
 *
 * \param target  A nick in common IRC server form like tim!root\@mycomain.com
 * \param nick    A buffer to hold the nickname.
 * \param size    A buffer size. If nick is longer than buffer size, it will 
 *                be truncated.
 *
 * For most events IRC server returns 'origin' (i.e. the person, who 
 * generated this event) in i.e. "common" form, like nick!host\@domain.
 * However, all the irc_cmd_* functions require just a nick/
 * This function parses this origin, and gets the nick, storing it into 
 * user-provided buffer.
 * A buffer of size 90 should be enough for most nicks :)
 *
 * \ingroup nnparse
 */
void irc_target_get_nick (const char * target, char *nick, size_t size);


/*!
 * \fn void irc_target_get_host (const char * target, char *nick, size_t size)
 * \brief Gets the host part from the target
 *
 * \param target  A nick in common IRC server form like tim!root\@mydomain.com
 * \param nick    A buffer to hold the nickname.
 * \param size    A buffer size. If nick is longer than buffer size, it will 
 *                be truncated.
 *
 * For most events IRC server returns 'origin' (i.e. the person, who 
 * generated this event) in i.e. "common" form, like nick!host\@domain.
 * I don't know any command, which requires host, but it may be useful :)
 * This function parses this origin, and gets the host, storing it into 
 * user-provided buffer.
 *
 * \ingroup nnparse
 */
void irc_target_get_host (const char * target, char *nick, size_t size);


/*!
 * \fn int irc_dcc_chat(irc_session_t * session, void * ctx, const char * nick, irc_dcc_callback_t callback, irc_dcc_t * dccid)
 * \brief Initiates a DCC CHAT.
 *
 * \param session An initiated and connected session.
 * \param ctx     A user-supplied DCC session context, which will be passed to 
 *                the DCC callback function. May be NULL.
 * \param nick    A nick to DCC CHAT with.
 * \param callback A DCC callback function, which will be called when 
 *                anything is said by other party. Must not be NULL.
 * \param dccid   On success, DCC session ID will be stored in this var.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * This function requests a DCC CHAT between you and other user. For 
 * newbies, DCC chat is like private chat, but it goes directly between
 * two users, and bypasses IRC server. DCC CHAT request must be accepted 
 * by other side before you can send anything.
 *
 * When the chat is accepted, terminated, or some data is received, the 
 * callback function is called. See the details in irc_dcc_callback_t 
 * declaration.
 *
 * Possible error responces for this command from the RFC1459:
 * - ::LIBIRC_RFC_ERR_NORECIPIENT
 * - ::LIBIRC_RFC_ERR_NOTEXTTOSEND
 * - ::LIBIRC_RFC_ERR_CANNOTSENDTOCHAN
 * - ::LIBIRC_RFC_ERR_NOTONCHANNEL
 * - ::LIBIRC_RFC_ERR_NOTOPLEVEL
 * - ::LIBIRC_RFC_ERR_WILDTOPLEVEL
 * - ::LIBIRC_RFC_ERR_TOOMANYTARGETS
 * - ::LIBIRC_RFC_ERR_NOSUCHNICK
 *
 * \sa irc_dcc_callback_t irc_dcc_msg
 * \ingroup dccstuff
 */
int irc_dcc_chat (irc_session_t * session, void * ctx, const char * nick, irc_dcc_callback_t callback, irc_dcc_t * dccid);


/*!
 * \fn int irc_dcc_msg	(irc_session_t * session, irc_dcc_t dccid, const char * text)
 * \brief Sends the message to the specific DCC CHAT
 *
 * \param session An IRC session.
 * \param dccid   A DCC session ID, which chat request must have been accepted.
 * \param text    Message text. Must not be NULL.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno().
 *
 * This function is used to send the DCC CHAT messages. DCC CHAT request
 * must be initiated and accepted first (or just accepted, if initiated by
 * other side).
 *
 * \sa irc_dcc_chat
 * \ingroup dccstuff
 */
int irc_dcc_msg	(irc_session_t * session, irc_dcc_t dccid, const char * text);


/*!
 * \fn int irc_dcc_accept (irc_session_t * session, irc_dcc_t dccid, void * ctx, irc_dcc_callback_t callback)
 * \brief Accepts a remote DCC CHAT or DCC RECVFILE request.
 *
 * \param session An initiated and connected session.
 * \param dccid   A DCC session ID, returned by appropriate callback.
 * \param ctx     A user-supplied DCC session context, which will be passed 
 *                to the DCC callback function. May be NULL.
 * \param callback A DCC callback function, which will be called when 
 *                anything is said by other party. Must not be NULL.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno().
 *
 * This function accepts a remote DCC request - either DCC CHAT or DCC FILE.
 * After the request is accepted, the supplied callback will be called,
 * and you can start sending messages or receiving the file.
 *
 * This function should be called only after either event_dcc_chat_req or
 * event_dcc_send_req events are generated, and should react to them. It is
 * possible not to call irc_dcc_accept or irc_dcc_decline immediately in 
 * callback function - you may just return, and call it later. However, to
 * prevent memory leaks, you must call either irc_dcc_decline or 
 * irc_dcc_accept for any incoming DCC request.
 * 
 * \sa irc_dcc_decline event_dcc_chat_req event_dcc_send_req
 * \ingroup dccstuff
 */
int	irc_dcc_accept (irc_session_t * session, irc_dcc_t dccid, void * ctx, irc_dcc_callback_t callback);


/*!
 * \fn int irc_dcc_decline (irc_session_t * session, irc_dcc_t dccid)
 * \brief Declines a remote DCC CHAT or DCC RECVFILE request.
 *
 * \param session An initiated and connected session.
 * \param dccid   A DCC session ID, returned by appropriate callback.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno().
 *
 * This function declines a remote DCC request - either DCC CHAT or DCC FILE.
 *
 * This function should be called only after either event_dcc_chat_req or
 * event_dcc_send_req events are generated, and should react to them. It is
 * possible not to call irc_dcc_accept or irc_dcc_decline immediately in 
 * callback function - you may just return, and call it later. However, to
 * prevent memory leaks, you must call either irc_dcc_decline or 
 * irc_dcc_accept for any incoming DCC request.
 *
 * Do not use this function to close the accepted or initiated DCC session.
 * Use irc_dcc_destroy instead.
 *
 * \sa irc_dcc_accept irc_callbacks_t::event_dcc_chat_req irc_callbacks_t::event_dcc_send_req irc_dcc_destroy
 * \ingroup dccstuff
 */
int irc_dcc_decline (irc_session_t * session, irc_dcc_t dccid);


/*!
 * \fn int irc_dcc_sendfile (irc_session_t * session, void * ctx, const char * nick, const char * filename, irc_dcc_callback_t callback, irc_dcc_t * dccid)
 * \brief Sends a file via DCC.
 *
 * \param session An initiated and connected session.
 * \param ctx     A user-supplied DCC session context, which will be passed to 
 *                the DCC callback function. May be NULL.
 * \param nick    A nick to send file via DCC to.
 * \param filename A file name to sent. Must be an existing file.
 * \param callback A DCC callback function, which will be called when 
 *                file sent operation is failed, progressed or completed.
 * \param dccid   On success, DCC session ID will be stored in this var.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno(). Any error, generated by the 
 *  IRC server, is available through irc_callbacks_t::event_numeric.
 *
 * This function generates a DCC SEND request to send the file. When it is
 * accepted, the file is sent to the remote party, and the DCC session is
 * closed. The send operation progress and result can be checked in 
 * callback. See the details in irc_dcc_callback_t declaration.
 *
 * Possible error responces for this command from the RFC1459:
 * - ::LIBIRC_RFC_ERR_NORECIPIENT
 * - ::LIBIRC_RFC_ERR_NOTEXTTOSEND
 * - ::LIBIRC_RFC_ERR_CANNOTSENDTOCHAN
 * - ::LIBIRC_RFC_ERR_NOTONCHANNEL
 * - ::LIBIRC_RFC_ERR_NOTOPLEVEL
 * - ::LIBIRC_RFC_ERR_WILDTOPLEVEL
 * - ::LIBIRC_RFC_ERR_TOOMANYTARGETS
 * - ::LIBIRC_RFC_ERR_NOSUCHNICK
 *
 * \sa irc_dcc_callback_t
 * \ingroup dccstuff
 */
int irc_dcc_sendfile (irc_session_t * session, void * ctx, const char * nick, const char * filename, irc_dcc_callback_t callback, irc_dcc_t * dccid);


/*!
 * \fn int irc_dcc_destroy (irc_session_t * session, irc_dcc_t dccid)
 * \brief Destroys a DCC session.
 *
 * \param session An initiated and connected session.
 * \param dccid   A DCC session ID.
 *
 * \return Return code 0 means success. Other value means error, the error 
 *  code may be obtained through irc_errno().
 *
 * This function closes the DCC connection (if available), and destroys
 * the DCC session, freeing the used resources. It can be called in any 
 * moment, even from callbacks or from different threads.
 *
 * Note that when DCC session is finished (either with success or failure),
 * you should not destroy it - it will be destroyed automatically.
 *
 * \ingroup dccstuff
 */
int irc_dcc_destroy (irc_session_t * session, irc_dcc_t dccid);


/*!
 * \fn void irc_get_version (unsigned int * high, unsigned int * low)
 * \brief Obtains a libircclient version.
 *
 * \param high A pointer to receive the high version part.
 * \param low  A pointer to receive the low version part.
 *
 * This function returns the libircclient version. You can use the version either
 * to check whether required options are available, or to output the version.
 * The preferred printf-like format string to output the version is:
 *
 * printf ("Version: %d.%02d", high, low);
 *
 * \ingroup common
 */
void irc_get_version (unsigned int * high, unsigned int * low);


/*!
 * \fn void irc_set_ctx (irc_session_t * session, void * ctx)
 * \brief Sets the IRC session context.
 *
 * \param session An initiated session.
 * \param ctx  A context.
 *
 * This function sets the user-defined context for this IRC session. This
 * context is not used by libircclient. Its purpose is to store session-specific
 * user data, which may be obtained later by calling irc_get_ctx().
 * Note that libircclient just 'carries out' this pointer. If you allocate some
 * memory, and store its address in ctx (most common usage), it is your 
 * responsibility to free it before calling irc_destroy_session().
 *
 * \sa irc_get_ctx
 * \ingroup contexts
 */
void irc_set_ctx (irc_session_t * session, void * ctx);


/*!
 * \fn void * irc_get_ctx (irc_session_t * session)
 * \brief Returns the IRC session context.
 *
 * \param session An initiated session.
 *
 * This function returns the IRC session context, which was set by 
 * irc_set_ctx(). If no context was set, this function returns NULL.
 *
 * \sa irc_set_ctx
 * \ingroup contexts
 */
void * irc_get_ctx (irc_session_t * session);


/*!
 * \fn int irc_errno (irc_session_t * session)
 * \brief Returns the last error code.
 *
 * \param session An initiated session.
 *
 * This function returns the last error code associated with last operation
 * of this IRC session. Possible error codes are defined in libirc_errors.h
 *
 * As usual, next errno rules apply:
 * - irc_errno() should be called ONLY if the called function fails;
 * - irc_errno() doesn't return 0 if function succeed; actually, the return
 *    value will be undefined.
 * - you should call irc_errno() IMMEDIATELY after function fails, before 
 *   calling any other libircclient function.
 *
 * \sa irc_strerror
 * \ingroup errors
 */
int irc_errno (irc_session_t * session);


/*!
 * \fn const char * irc_strerror (int ircerrno)
 * \brief Returns the text error message associated with this error code.
 *
 * \param ircerrno A numeric error code returned by irc_errno()
 *
 * This function returns the text representation of the given error code.
 *
 * \sa irc_errno()
 * \ingroup errors
 */
const char * irc_strerror (int ircerrno);


/*!
 * \fn void irc_option_set (irc_session_t * session, unsigned int option)
 * \brief Sets the libircclient option.
 *
 * \param session An initiated session.
 * \param option  An option from libirc_options.h
 *
 * This function sets the libircclient option, changing libircclient behavior. See the
 * option list for the meaning for every option.
 *
 * \sa irc_option_reset
 * \ingroup options
 */
void irc_option_set (irc_session_t * session, unsigned int option);


/*!
 * \fn void irc_option_reset (irc_session_t * session, unsigned int option)
 * \brief Resets the libircclient option.
 *
 * \param session An initiated session.
 * \param option  An option from libirc_options.h
 *
 * This function removes the previously set libircclient option, changing libircclient 
 * behavior. See the option list for the meaning for every option.
 *
 * \sa irc_option_set
 * \ingroup options
 */
void irc_option_reset (irc_session_t * session, unsigned int option);


/*!
 * \fn char * irc_color_strip_from_mirc (const char * message)
 * \brief Removes all the color codes and format options.
 *
 * \param message A message from IRC
 *
 * \return Returns a new plain text message with stripped mIRC color codes.
 * Note that the memory for the new message is allocated using malloc(), so
 * you should free it using free() when it is not used anymore. If memory 
 * allocation failed, returns 0.
 *
 * \sa irc_color_convert_from_mirc irc_color_convert_to_mirc
 * \ingroup colors
 */
char * irc_color_strip_from_mirc (const char * message);


/*!
 * \fn char * irc_color_convert_from_mirc (const char * message)
 * \brief Converts all the color codes and format options to libircclient colors.
 *
 * \param message A message from IRC
 *
 * \return Returns a new message with converted mIRC color codes and format
 * options. See the irc_color_convert_to_mirc() help to see how the colors 
 * are converted.\n
 * Note that the memory for the new message is allocated using malloc(), so
 * you should free it using free() when it is not used anymore. If memory 
 * allocation failed, returns 0.
 *
 * \sa irc_color_strip_from_mirc irc_color_convert_to_mirc
 * \ingroup colors
 */
char * irc_color_convert_from_mirc (const char * message);


/*!
 * \fn char * irc_color_convert_to_mirc (const char * message)
 * \brief Converts all the color codes from libircclient format to mIRC.
 *
 * \param message A message with color codes
 *
 * \return Returns a new message with converted color codes and format
 * options, or 0 if memory could not be allocated. Note that the memory for 
 * the new message is allocated using malloc(), so you should free it using 
 * free() when it is not used anymore.
 *
 * The color system of libircclient is designed to be easy to use, and 
 * portable between different IRC clients. Every color or format option is 
 * described using plain text commands written between square brackets. The 
 * possible codes are:
 * - [B] ... [/B] - bold format mode. Everything between [B] and [/B] is written in \b bold.
 * - [I] ... [/I] - italic/reverse format mode. Everything between [I] and [/I] is written in \c italic, or reversed (however, because some clients are incapable of rendering italic text, most clients display this as normal text with the background and foreground colors swapped).
 * - [U] ... [/U] - underline format mode. Everything between [U] and [/U] is written underlined.
 * - [COLOR=RED] ... [/COLOR] - write the text using specified foreground color. The color is set by using the \c COLOR keyword, and equal sign followed by text color code (see below).
 * - [COLOR=RED/BLUE] ... [/COLOR] - write the text using specified foreground and background color. The color is set by using the \c COLOR keyword, an equal sign followed by text foreground color code, a dash and a text background color code.
 * 
 * The supported text colors are:
 * - WHITE
 * - BLACK
 * - DARKBLUE
 * - DARKGREEN
 * - RED
 * - BROWN
 * - PURPLE
 * - OLIVE
 * - YELLOW
 * - GREEN
 * - TEAL
 * - CYAN
 * - BLUE
 * - MAGENTA
 * - DARKGRAY
 * - LIGHTGRAY
 * 
 * Examples of color sequences:
 * \code
 * Hello, [B]Tim[/B]. 
 * [U]Arsenal[/U] got a [COLOR=RED]red card[/COLOR]
 * The tree[U]s[/U] are [COLOR=GREEN/BLACK]green[/COLOR]
 * \endcode
 *
 * \sa irc_color_strip_from_mirc irc_color_convert_from_mirc
 * \ingroup colors
 */
char * irc_color_convert_to_mirc (const char * message);

#ifdef	__cplusplus
}
#endif

#endif /* INCLUDE_LIBIRC_H */
