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

#define LIBIRC_DCC_CHAT			1
#define LIBIRC_DCC_SENDFILE		2
#define LIBIRC_DCC_RECVFILE		3


static irc_dcc_session_t * libirc_find_dcc_session (irc_session_t * session, irc_dcc_t dccid, int lock_list)
{
	irc_dcc_session_t * s, *found = 0;

	if ( lock_list )
		libirc_mutex_lock (&session->mutex_dcc);

	for ( s = session->dcc_sessions; s; s = s->next )
	{
		if ( s->id == dccid )
		{
			found = s;
			break;
		}
	}

	if ( found == 0 && lock_list )
		libirc_mutex_unlock (&session->mutex_dcc);

	return found;
}


static void libirc_dcc_destroy_nolock (irc_session_t * session, irc_dcc_t dccid)
{
	irc_dcc_session_t * dcc = libirc_find_dcc_session (session, dccid, 0);

	if ( dcc )
	{
		if ( dcc->sock >= 0 )
			socket_close (&dcc->sock);

		dcc->state = LIBIRC_STATE_REMOVED;
	}
}


static void libirc_remove_dcc_session (irc_session_t * session, irc_dcc_session_t * dcc, int lock_list)
{
	if ( dcc->sock >= 0 )
		socket_close (&dcc->sock);

	if ( dcc->dccsend_file_fp )
		fclose (dcc->dccsend_file_fp);

	dcc->dccsend_file_fp = 0;

	libirc_mutex_destroy (&dcc->mutex_outbuf);

	if ( lock_list )
		libirc_mutex_lock (&session->mutex_dcc);

	if ( session->dcc_sessions != dcc )
	{
		irc_dcc_session_t * s;
		for ( s = session->dcc_sessions; s; s = s->next )
		{
			if ( s->next == dcc )
			{
				s->next = dcc->next;
				break;
			}
		}
	}
	else
		session->dcc_sessions = dcc->next;

	if ( lock_list )
		libirc_mutex_unlock (&session->mutex_dcc);

	free (dcc);
}


static void libirc_dcc_add_descriptors (irc_session_t * ircsession, fd_set *in_set, fd_set *out_set, int * maxfd)
{
	irc_dcc_session_t * dcc, *dcc_next;
	time_t now = time (0);

	libirc_mutex_lock (&ircsession->mutex_dcc);

	// Preprocessing DCC list:
	// - ask DCC send callbacks for data;
	// - remove unused DCC structures
	for ( dcc = ircsession->dcc_sessions; dcc; dcc = dcc_next )
	{
		dcc_next = dcc->next;

		// Remove timed-out sessions
		if ( (dcc->state == LIBIRC_STATE_CONNECTING
			|| dcc->state == LIBIRC_STATE_INIT
			|| dcc->state == LIBIRC_STATE_LISTENING)
		&& now - dcc->timeout > ircsession->dcc_timeout )
		{
			// Inform the caller about DCC timeout.
			// Do not inform when state is LIBIRC_STATE_INIT - session
			// was initiated from someone else, and callbacks aren't set yet.
			if ( dcc->state != LIBIRC_STATE_INIT )
			{
				libirc_mutex_unlock (&ircsession->mutex_dcc);

				if ( dcc->cb )
					(*dcc->cb)(ircsession, dcc->id, LIBIRC_ERR_TIMEOUT, dcc->ctx, 0, 0);

				libirc_mutex_lock (&ircsession->mutex_dcc);
			}

			libirc_remove_dcc_session (ircsession, dcc, 0);
		}

		/*
		 * If we're sending file, and the output buffer is empty, we need
         * to provide some data.
         */
		if ( dcc->state == LIBIRC_STATE_CONNECTED
		&& dcc->dccmode == LIBIRC_DCC_SENDFILE
		&& dcc->dccsend_file_fp
		&& dcc->outgoing_offset == 0 )
		{
			int len = fread (dcc->outgoing_buf, 1, sizeof (dcc->outgoing_buf), dcc->dccsend_file_fp);

			if ( len <= 0 )
			{
				int err = (len < 0 ? LIBIRC_ERR_READ : 0);
			
				libirc_mutex_unlock (&ircsession->mutex_dcc);

				(*dcc->cb)(ircsession, dcc->id, err, dcc->ctx, 0, 0);
				libirc_mutex_lock (&ircsession->mutex_dcc);
				libirc_dcc_destroy_nolock (ircsession, dcc->id);
			}
			else
				dcc->outgoing_offset = len;
		}

		// Clean up unused sessions
		if ( dcc->state == LIBIRC_STATE_REMOVED )
			libirc_remove_dcc_session (ircsession, dcc, 0);
	}

	for ( dcc = ircsession->dcc_sessions; dcc; dcc = dcc->next )
	{
		switch (dcc->state)
		{
		case LIBIRC_STATE_LISTENING:
			// While listening, only in_set descriptor should be set
			libirc_add_to_set (dcc->sock, in_set, maxfd);
			break;

		case LIBIRC_STATE_CONNECTING:
			// While connection, only out_set descriptor should be set
			libirc_add_to_set (dcc->sock, out_set, maxfd);
			break;

		case LIBIRC_STATE_CONNECTED:
			// Add input descriptor if there is space in input buffer
			// and it is DCC chat (during DCC send, there is nothing to recv)
			if ( dcc->incoming_offset < sizeof(dcc->incoming_buf) - 1 )
				libirc_add_to_set (dcc->sock, in_set, maxfd);

			// Add output descriptor if there is something in output buffer
			libirc_mutex_lock (&dcc->mutex_outbuf);

			if ( dcc->outgoing_offset > 0  )
				libirc_add_to_set (dcc->sock, out_set, maxfd);

			libirc_mutex_unlock (&dcc->mutex_outbuf);
			break;

		case LIBIRC_STATE_CONFIRM_SIZE:
			/*
			 * If we're receiving file, then WE should confirm the transferred
             * part (so we have to sent data). But if we're sending the file, 
             * then RECEIVER should confirm the packet, so we have to receive
             * data.
             *
             * We don't need to LOCK_DCC_OUTBUF - during file transfer, buffers
             * can't change asynchronously.
             */
             if ( dcc->dccmode == LIBIRC_DCC_RECVFILE && dcc->outgoing_offset > 0 )
             	libirc_add_to_set (dcc->sock, out_set, maxfd);

             if ( dcc->dccmode == LIBIRC_DCC_SENDFILE && dcc->incoming_offset < 4 )
				libirc_add_to_set (dcc->sock, in_set, maxfd);
		}
	}

	libirc_mutex_unlock (&ircsession->mutex_dcc);
}


static void libirc_dcc_process_descriptors (irc_session_t * ircsession, fd_set *in_set, fd_set *out_set)
{
	irc_dcc_session_t * dcc;

	/*
	 * We need to use such a complex scheme here, because on every callback
     * a number of DCC sessions could be destroyed.
     */
	libirc_mutex_lock (&ircsession->mutex_dcc);

	for ( dcc = ircsession->dcc_sessions; dcc; dcc = dcc->next )
	{
		if ( dcc->state == LIBIRC_STATE_LISTENING
		&& FD_ISSET (dcc->sock, in_set) )
		{
			socklen_t len = sizeof(dcc->remote_addr);
			int nsock, err = 0;

			// New connection is available; accept it.
			if ( socket_accept (&dcc->sock, &nsock, (struct sockaddr *) &dcc->remote_addr, &len) )
				err = LIBIRC_ERR_ACCEPT;

			// On success, change the active socket and change the state
			if ( err == 0 )
			{
				// close the listen socket, and replace it by a newly 
				// accepted
				socket_close (&dcc->sock);
				dcc->sock = nsock;
				dcc->state = LIBIRC_STATE_CONNECTED;
			}

			// If this is DCC chat, inform the caller about accept() 
			// success or failure.
			// Otherwise (DCC send) there is no reason.
			if ( dcc->dccmode == LIBIRC_DCC_CHAT )
			{
				libirc_mutex_unlock (&ircsession->mutex_dcc);
				(*dcc->cb)(ircsession, dcc->id, err, dcc->ctx, 0, 0);
				libirc_mutex_lock (&ircsession->mutex_dcc);
			}

			if ( err )
				libirc_dcc_destroy_nolock (ircsession, dcc->id);
		}

		if ( dcc->state == LIBIRC_STATE_CONNECTING
		&& FD_ISSET (dcc->sock, out_set) )
		{
			// Now we have to determine whether the socket is connected 
			// or the connect is failed
			struct sockaddr_in saddr;
			socklen_t slen = sizeof(saddr);
			int err = 0;

			if ( getpeername (dcc->sock, (struct sockaddr*)&saddr, &slen) < 0 )
				err = LIBIRC_ERR_CONNECT;

			// On success, change the state
			if ( err == 0 )
				dcc->state = LIBIRC_STATE_CONNECTED;

			// If this is DCC chat, inform the caller about connect()
			// success or failure.
			// Otherwise (DCC send) there is no reason.
			if ( dcc->dccmode == LIBIRC_DCC_CHAT )
			{
				libirc_mutex_unlock (&ircsession->mutex_dcc);
				(*dcc->cb)(ircsession, dcc->id, err, dcc->ctx, 0, 0);
				libirc_mutex_lock (&ircsession->mutex_dcc);
			}

			if ( err )
				libirc_dcc_destroy_nolock (ircsession, dcc->id);
		}

		if ( dcc->state == LIBIRC_STATE_CONNECTED
		|| dcc->state == LIBIRC_STATE_CONFIRM_SIZE )
		{
			if ( FD_ISSET (dcc->sock, in_set) )
			{
				int length, offset = 0, err = 0;
		
				unsigned int amount = sizeof (dcc->incoming_buf) - dcc->incoming_offset;

				length = socket_recv (&dcc->sock, dcc->incoming_buf + dcc->incoming_offset, amount);

				if ( length < 0 )
				{
					err = LIBIRC_ERR_READ;
				}	
				else if ( length == 0 )
				{
					err = LIBIRC_ERR_CLOSED;

					if ( dcc->dccsend_file_fp )
					{
						fclose (dcc->dccsend_file_fp);
						dcc->dccsend_file_fp = 0;
					}
				}
				else
				{
					dcc->incoming_offset += length;

					if ( dcc->dccmode != LIBIRC_DCC_CHAT )
						offset = dcc->incoming_offset;
					else
						offset = libirc_findcrorlf (dcc->incoming_buf, dcc->incoming_offset);

					/*
					 * In LIBIRC_STATE_CONFIRM_SIZE state we don't call any
                     * callbacks (except there is an error). We just receive
                     * the data, and compare it with the amount sent.
                     */
					if ( dcc->state == LIBIRC_STATE_CONFIRM_SIZE )
					{
						if ( dcc->dccmode != LIBIRC_DCC_SENDFILE )
							abort();

						if ( dcc->incoming_offset == 4 )
						{
							// The order is big-endian
							const unsigned char * bptr = (const unsigned char *) dcc->incoming_buf;
							unsigned int received_size = (bptr[0] << 24) | (bptr[1] << 16) | (bptr[2] << 8)  | bptr[3];

							// Sent size confirmed
							if ( dcc->file_confirm_offset == received_size )
							{
								dcc->state = LIBIRC_STATE_CONNECTED;
								dcc->incoming_offset = 0;
							}
							else
								err = LIBIRC_ERR_WRITE;
						}
					}
					else
					{
						/*
						 * If it is DCC_CHAT, we send a 0-terminated string 
						 * (which is smaller than offset). Otherwise we send
	                     * a full buffer. 
	                     */
						libirc_mutex_unlock (&ircsession->mutex_dcc);

						if ( dcc->dccmode != LIBIRC_DCC_CHAT )
						{
							if ( dcc->dccmode != LIBIRC_DCC_RECVFILE )
								abort();

							(*dcc->cb)(ircsession, dcc->id, err, dcc->ctx, dcc->incoming_buf, offset);

                            /*
                             * If the session is not terminated in callback,
                             * put the sent amount into the sent_packet_size_net_byteorder
                             */
                             if ( dcc->state != LIBIRC_STATE_REMOVED )
                             {
                             	dcc->state = LIBIRC_STATE_CONFIRM_SIZE;
                             	dcc->file_confirm_offset += offset;
								
								// Store as big endian
								dcc->outgoing_buf[0] = (char) dcc->file_confirm_offset >> 24;
								dcc->outgoing_buf[1] = (char) dcc->file_confirm_offset >> 16;
								dcc->outgoing_buf[2] = (char) dcc->file_confirm_offset >> 8;
								dcc->outgoing_buf[3] = (char) dcc->file_confirm_offset;
                             	dcc->outgoing_offset = 4;
							}
						}
						else
							(*dcc->cb)(ircsession, dcc->id, err, dcc->ctx, dcc->incoming_buf, strlen(dcc->incoming_buf));

						libirc_mutex_lock (&ircsession->mutex_dcc);

						if ( dcc->incoming_offset - offset > 0 )
							memmove (dcc->incoming_buf, dcc->incoming_buf + offset, dcc->incoming_offset - offset);

						dcc->incoming_offset -= offset;
					}
				}

                /*
                 * If error arises somewhere above, we inform the caller 
                 * of failure, and destroy this session.
                 */
				if ( err )
				{
					libirc_mutex_unlock (&ircsession->mutex_dcc);
					(*dcc->cb)(ircsession, dcc->id, err, dcc->ctx, 0, 0);
					libirc_mutex_lock (&ircsession->mutex_dcc);
					libirc_dcc_destroy_nolock (ircsession, dcc->id);
				}
			}

            /*
             * Session might be closed (with sock = -1) after the in_set 
             * processing, so before out_set processing we should check
             * for this case
			 */
			if ( dcc->state == LIBIRC_STATE_REMOVED )
				continue;

			/*
			 * Write bit set - we can send() something, and it won't block.
             */
			if ( FD_ISSET (dcc->sock, out_set) )
			{
				int length, offset, err = 0;

				/*
				 * Because in some cases outgoing_buf could be changed 
				 * asynchronously (by another thread), we should lock 
				 * it.
                 */
				libirc_mutex_lock (&dcc->mutex_outbuf);

				offset = dcc->outgoing_offset;
		
				if ( offset > 0 )
				{
					length = socket_send (&dcc->sock, dcc->outgoing_buf, offset);

					if ( length < 0 )
						err = LIBIRC_ERR_WRITE;
					else if ( length == 0 )
						err = LIBIRC_ERR_CLOSED;
					else
					{
						/*
						 * If this was DCC_SENDFILE, and we just sent a packet,
						 * change the state to wait for confirmation (and store
						 * sent packet size)
	                     */
						if ( dcc->state == LIBIRC_STATE_CONNECTED
						&& dcc->dccmode == LIBIRC_DCC_SENDFILE )
						{
							dcc->file_confirm_offset += offset;
							dcc->state = LIBIRC_STATE_CONFIRM_SIZE;

							libirc_mutex_unlock (&ircsession->mutex_dcc);
							libirc_mutex_unlock (&dcc->mutex_outbuf);
							(*dcc->cb)(ircsession, dcc->id, err, dcc->ctx, 0, offset);
							libirc_mutex_lock (&ircsession->mutex_dcc);
							libirc_mutex_lock (&dcc->mutex_outbuf);
						}

						if ( dcc->outgoing_offset - length > 0 )
							memmove (dcc->outgoing_buf, dcc->outgoing_buf + length, dcc->outgoing_offset - length);

						dcc->outgoing_offset -= length;

						/*
						 * If we just sent the confirmation data, change state 
						 * back.
                         */
						if ( dcc->state == LIBIRC_STATE_CONFIRM_SIZE
						&& dcc->dccmode == LIBIRC_DCC_RECVFILE
						&& dcc->outgoing_offset == 0 )
						{
							/*
							 * If the file is already received, we should inform
                             * the caller, and close the session.
                             */
							if ( dcc->received_file_size == dcc->file_confirm_offset )
                            {
								libirc_mutex_unlock (&ircsession->mutex_dcc);
								libirc_mutex_unlock (&dcc->mutex_outbuf);
								(*dcc->cb)(ircsession, dcc->id, 0, dcc->ctx, 0, 0);
								libirc_dcc_destroy_nolock (ircsession, dcc->id);
                            }
                            else
                            {
                            	/* Continue to receive the file */
								dcc->state = LIBIRC_STATE_CONNECTED;
							}
						}
					}
				}

				libirc_mutex_unlock (&dcc->mutex_outbuf);

                /*
                 * If error arises somewhere above, we inform the caller 
                 * of failure, and destroy this session.
                 */
				if ( err )
				{
					libirc_mutex_unlock (&ircsession->mutex_dcc);
					(*dcc->cb)(ircsession, dcc->id, err, dcc->ctx, 0, 0);
					libirc_mutex_lock (&ircsession->mutex_dcc);

					libirc_dcc_destroy_nolock (ircsession, dcc->id);
				}
			}
		}
	}

	libirc_mutex_unlock (&ircsession->mutex_dcc);
}


static int libirc_new_dcc_session (irc_session_t * session, unsigned long ip, unsigned short port, int dccmode, void * ctx, irc_dcc_session_t ** pdcc)
{
	irc_dcc_session_t * dcc = (irc_dcc_session_t*)malloc (sizeof(irc_dcc_session_t));

	if ( !dcc )
		return LIBIRC_ERR_NOMEM;

	// setup
	memset (dcc, 0, sizeof(irc_dcc_session_t));

	dcc->dccsend_file_fp = 0;

	if ( libirc_mutex_init (&dcc->mutex_outbuf) )
		goto cleanup_exit_error;

	if ( socket_create (PF_INET, SOCK_STREAM, &dcc->sock) )
		goto cleanup_exit_error;

	if ( !ip )
	{
		unsigned long arg = 1;

		setsockopt (dcc->sock, SOL_SOCKET, SO_REUSEADDR, (char*)&arg, sizeof(arg));

#if defined (ENABLE_IPV6)
		if ( session->flags & SESSIONFL_USES_IPV6 )
		{
			struct sockaddr_in6 saddr6;

			memset (&saddr6, 0, sizeof(saddr6));
			saddr6.sin6_family = AF_INET6;
			memcpy (&saddr6.sin6_addr, &session->local_addr6, sizeof(session->local_addr6));
			saddr6.sin6_port = htons (0);

			if ( bind (dcc->sock, (struct sockaddr *) &saddr6, sizeof(saddr6)) < 0 )
				goto cleanup_exit_error;
		}
		else
#endif
		{
			struct sockaddr_in saddr;
			memset (&saddr, 0, sizeof(saddr));
			saddr.sin_family = AF_INET;
			memcpy (&saddr.sin_addr, &session->local_addr, sizeof(session->local_addr));
			saddr.sin_port = htons (0);

			if ( bind (dcc->sock, (struct sockaddr *) &saddr, sizeof(saddr)) < 0 )
				goto cleanup_exit_error;
		}

		if ( listen (dcc->sock, 5) < 0 )
			goto cleanup_exit_error;

		dcc->state = LIBIRC_STATE_LISTENING;
	}
	else
	{
		// make socket non-blocking, so connect() call won't block
		if ( socket_make_nonblocking (&dcc->sock) )
			goto cleanup_exit_error;

		memset (&dcc->remote_addr, 0, sizeof(dcc->remote_addr));
		dcc->remote_addr.sin_family = AF_INET;
		dcc->remote_addr.sin_addr.s_addr = htonl (ip); // what idiot came up with idea to send IP address in host-byteorder?
        dcc->remote_addr.sin_port = htons(port);

		dcc->state = LIBIRC_STATE_INIT;
	}

	dcc->dccmode = dccmode;
	dcc->ctx = ctx;
	time (&dcc->timeout);

	// and store it
	libirc_mutex_lock (&session->mutex_dcc);

	dcc->id = session->dcc_last_id++;
	dcc->next = session->dcc_sessions;
	session->dcc_sessions = dcc;

	libirc_mutex_unlock (&session->mutex_dcc);

    *pdcc = dcc;
    return 0;

cleanup_exit_error:
	if ( dcc->sock >= 0 )
		socket_close (&dcc->sock);

	free (dcc);
	return LIBIRC_ERR_SOCKET;
}


int irc_dcc_destroy (irc_session_t * session, irc_dcc_t dccid)
{
	// This function doesn't actually destroy the session; it just changes
	// its state to "removed" and closes the socket. The memory is actually
	// freed after the processing loop.
	irc_dcc_session_t * dcc = libirc_find_dcc_session (session, dccid, 1);

	if ( !dcc )
		return 1;

	if ( dcc->sock >= 0 )
		socket_close (&dcc->sock);

	dcc->state = LIBIRC_STATE_REMOVED;

	libirc_mutex_unlock (&session->mutex_dcc);
	return 0;
}


int	irc_dcc_chat (irc_session_t * session, void * ctx, const char * nick, irc_dcc_callback_t callback, irc_dcc_t * dccid)
{
	struct sockaddr_in saddr;
	socklen_t len = sizeof(saddr);
	char cmdbuf[128], notbuf[128];
	irc_dcc_session_t * dcc;
	int err;

	if ( session->state != LIBIRC_STATE_CONNECTED )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		return 1;
	}

	err = libirc_new_dcc_session (session, 0, 0, LIBIRC_DCC_CHAT, ctx, &dcc);

	if ( err )
	{
		session->lasterror = err;
		return 1;
	}

	if ( getsockname (dcc->sock, (struct sockaddr*) &saddr, &len) < 0 )
	{
		session->lasterror = LIBIRC_ERR_SOCKET;
		libirc_remove_dcc_session (session, dcc, 1);
		return 1;
	}

	sprintf (notbuf, "DCC Chat (%s)", inet_ntoa (saddr.sin_addr));
	sprintf (cmdbuf, "DCC CHAT chat %lu %u", (unsigned long) ntohl (saddr.sin_addr.s_addr), ntohs (saddr.sin_port));

	if ( irc_cmd_notice (session, nick, notbuf)
	|| irc_cmd_ctcp_request (session, nick, cmdbuf) )
	{
		libirc_remove_dcc_session (session, dcc, 1);
		return 1;
	}

	*dccid = dcc->id;
	dcc->cb = callback;
	dcc->dccmode = LIBIRC_DCC_CHAT;

	return 0;
}


int irc_dcc_msg	(irc_session_t * session, irc_dcc_t dccid, const char * text)
{
	irc_dcc_session_t * dcc = libirc_find_dcc_session (session, dccid, 1);

	if ( !dcc )
		return 1;

	if ( dcc->dccmode != LIBIRC_DCC_CHAT )
	{
		session->lasterror = LIBIRC_ERR_INVAL;
		libirc_mutex_unlock (&session->mutex_dcc);
		return 1;
	}

	if ( (strlen(text) + 2) >= (sizeof(dcc->outgoing_buf) - dcc->outgoing_offset) )
	{
		session->lasterror = LIBIRC_ERR_NOMEM;
		libirc_mutex_unlock (&session->mutex_dcc);
		return 1;
	}

	libirc_mutex_lock (&dcc->mutex_outbuf);

	strcpy (dcc->outgoing_buf + dcc->outgoing_offset, text);
	dcc->outgoing_offset += strlen (text);
	dcc->outgoing_buf[dcc->outgoing_offset++] = 0x0D;
	dcc->outgoing_buf[dcc->outgoing_offset++] = 0x0A;

	libirc_mutex_unlock (&dcc->mutex_outbuf);
	libirc_mutex_unlock (&session->mutex_dcc);

	return 0;
}


static void libirc_dcc_request (irc_session_t * session, const char * nick, const char * req)
{
	char filenamebuf[256];
	unsigned long ip, size;
	unsigned short port;

	if ( sscanf (req, "DCC CHAT chat %lu %hu", &ip, &port) == 2 )
	{
		if ( session->callbacks.event_dcc_chat_req )
		{
			irc_dcc_session_t * dcc;

			int err = libirc_new_dcc_session (session, ip, port, LIBIRC_DCC_CHAT, 0, &dcc);
			if ( err )
			{
				session->lasterror = err;
				return;
			}

			(*session->callbacks.event_dcc_chat_req) (session, 
						nick, 
						inet_ntoa (dcc->remote_addr.sin_addr),
						dcc->id);
		}

		return;
	}
	else if ( sscanf (req, "DCC SEND %s %lu %hu %lu", filenamebuf, &ip, &port, &size) == 4 )
	{
		if ( session->callbacks.event_dcc_send_req )
		{
			irc_dcc_session_t * dcc;

			int err = libirc_new_dcc_session (session, ip, port, LIBIRC_DCC_RECVFILE, 0, &dcc);
			if ( err )
			{
				session->lasterror = err;
				return;
			}

			(*session->callbacks.event_dcc_send_req) (session, 
						nick, 
						inet_ntoa (dcc->remote_addr.sin_addr),
						filenamebuf,
						size,
						dcc->id);

			dcc->received_file_size = size;
		}

		return;
	}
#if defined (ENABLE_DEBUG)
	fprintf (stderr, "BUG: Unhandled DCC message: %s\n", req);
	abort();
#endif
}


int	irc_dcc_accept (irc_session_t * session, irc_dcc_t dccid, void * ctx, irc_dcc_callback_t callback)
{
	irc_dcc_session_t * dcc = libirc_find_dcc_session (session, dccid, 1);

	if ( !dcc )
		return 1;

	if ( dcc->state != LIBIRC_STATE_INIT )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		libirc_mutex_unlock (&session->mutex_dcc);
		return 1;
	}

	dcc->cb = callback;
	dcc->ctx = ctx;

	// Initiate the connect
    if ( socket_connect (&dcc->sock, (struct sockaddr *) &dcc->remote_addr, sizeof(dcc->remote_addr)) )
	{
		libirc_dcc_destroy_nolock (session, dccid);
		libirc_mutex_unlock (&session->mutex_dcc);
		session->lasterror = LIBIRC_ERR_CONNECT;
		return 1;
	}

	dcc->state = LIBIRC_STATE_CONNECTING;
	libirc_mutex_unlock (&session->mutex_dcc);
	return 0;
}


int	irc_dcc_decline (irc_session_t * session, irc_dcc_t dccid)
{
	irc_dcc_session_t * dcc = libirc_find_dcc_session (session, dccid, 1);

	if ( !dcc )
		return 1;

	if ( dcc->state != LIBIRC_STATE_INIT )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		libirc_mutex_unlock (&session->mutex_dcc);
		return 1;
	}

	libirc_dcc_destroy_nolock (session, dccid);
	libirc_mutex_unlock (&session->mutex_dcc);
	return 0;
}


int	irc_dcc_sendfile (irc_session_t * session, void * ctx, const char * nick, const char * filename, irc_dcc_callback_t callback, irc_dcc_t * dccid)
{
	struct sockaddr_in saddr;
	socklen_t len = sizeof(saddr);
	char cmdbuf[128], notbuf[128];
	irc_dcc_session_t * dcc;
	const char * p;
	int err;
	long filesize;

	if ( !session || !dccid || !filename || !callback )
	{
		session->lasterror = LIBIRC_ERR_INVAL;
		return 1;
	}

	if ( session->state != LIBIRC_STATE_CONNECTED )
	{
		session->lasterror = LIBIRC_ERR_STATE;
		return 1;
	}

	if ( (err = libirc_new_dcc_session (session, 0, 0, LIBIRC_DCC_SENDFILE, ctx, &dcc)) != 0 )
	{
		session->lasterror = err;
		return 1;
	}

	if ( (dcc->dccsend_file_fp = fopen (filename, "rb")) == 0 )
	{
		libirc_remove_dcc_session (session, dcc, 1);
		session->lasterror = LIBIRC_ERR_OPENFILE;
		return 1;
	}

	/* Get file length */
	if ( fseek (dcc->dccsend_file_fp, 0, SEEK_END)
	|| (filesize = ftell (dcc->dccsend_file_fp)) == -1
	|| fseek (dcc->dccsend_file_fp, 0, SEEK_SET) )
	{
		libirc_remove_dcc_session (session, dcc, 1);
		session->lasterror = LIBIRC_ERR_NODCCSEND;
		return 1;
	}

	if ( getsockname (dcc->sock, (struct sockaddr*) &saddr, &len) < 0 )
	{
		libirc_remove_dcc_session (session, dcc, 1);
		session->lasterror = LIBIRC_ERR_SOCKET;
		return 1;
	}

	// Remove path from the filename
	if ( (p = strrchr (filename, '\\')) == 0
	&& (p = strrchr (filename, '/')) == 0 )
		p = filename;
	else
		p++; // skip directory slash

	sprintf (notbuf, "DCC Send %s (%s)", p, inet_ntoa (saddr.sin_addr));
	sprintf (cmdbuf, "DCC SEND %s %lu %u %ld", p, (unsigned long) ntohl (saddr.sin_addr.s_addr), ntohs (saddr.sin_port), filesize);

	if ( irc_cmd_notice (session, nick, notbuf)
	|| irc_cmd_ctcp_request (session, nick, cmdbuf) )
	{
		libirc_remove_dcc_session (session, dcc, 1);
		return 1;
	}

	*dccid = dcc->id;
	dcc->cb = callback;

	return 0;
}
