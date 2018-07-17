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


#if defined (ENABLE_SSL)

// Nonzero if OpenSSL has been initialized
static SSL_CTX * ssl_context = 0;

#if defined (_WIN32)
#include <windows.h>
// This array will store all of the mutexes available to OpenSSL
static CRITICAL_SECTION * mutex_buf = 0;

// OpenSSL callback to utilize static locks
static void cb_openssl_locking_function( int mode, int n, const char * file, int line )
{
    if ( mode & CRYPTO_LOCK)
        EnterCriticalSection( &mutex_buf[n] );
    else
        LeaveCriticalSection( &mutex_buf[n] );
}

// OpenSSL callback to get the thread ID
static unsigned long cb_openssl_id_function()
{
    return ((unsigned long) GetCurrentThreadId() );
}

static int alloc_mutexes( unsigned int total )
{
	int i;
	
	// Enable thread safety in OpenSSL
	mutex_buf = (CRITICAL_SECTION*) malloc( total * sizeof(CRITICAL_SECTION) );

	if ( !mutex_buf )
		return -1;

	for ( i = 0;  i < total;  i++)
		InitializeCriticalSection( &(mutex_buf[i]) );
	
	return 0;
}


#else

// This array will store all of the mutexes available to OpenSSL
static pthread_mutex_t * mutex_buf = 0;

// OpenSSL callback to utilize static locks
static void cb_openssl_locking_function( int mode, int n, const char * file, int line )
{
    if ( mode & CRYPTO_LOCK)
        pthread_mutex_lock( &mutex_buf[n] );
    else
        pthread_mutex_unlock( &mutex_buf[n] );
}

// OpenSSL callback to get the thread ID
static unsigned long cb_openssl_id_function()
{
    return ((unsigned long) pthread_self() );
}

static int alloc_mutexes( unsigned int total )
{
	int i;
	
	// Enable thread safety in OpenSSL
	mutex_buf = (pthread_mutex_t*) malloc( total * sizeof(pthread_mutex_t) );

	if ( !mutex_buf )
		return -1;

	for ( i = 0;  i < total;  i++)
		pthread_mutex_init( &(mutex_buf[i]), 0 );
	
	return 0;
}

#endif

static int ssl_init_context( irc_session_t * session )
{
	// Load the strings and init the library
	SSL_load_error_strings();

	// Enable thread safety in OpenSSL
	if ( alloc_mutexes( CRYPTO_num_locks() ) )
		return LIBIRC_ERR_NOMEM;

	// Register our callbacks
	CRYPTO_set_id_callback( cb_openssl_id_function );
	CRYPTO_set_locking_callback( cb_openssl_locking_function );

	// Init it
	if ( !SSL_library_init() )
		return LIBIRC_ERR_SSL_INIT_FAILED;

	if ( RAND_status() == 0 )
		return LIBIRC_ERR_SSL_INIT_FAILED;

	// Create an SSL context; currently a single context is used for all connections
	ssl_context = SSL_CTX_new( SSLv23_method() );

	if ( !ssl_context )
		return LIBIRC_ERR_SSL_INIT_FAILED;

	// Disable SSLv2 as it is unsecure
	if ( (SSL_CTX_set_options( ssl_context, SSL_OP_NO_SSLv2) & SSL_OP_NO_SSLv2) == 0 )
		return LIBIRC_ERR_SSL_INIT_FAILED;

	// Enable only strong ciphers
	if ( SSL_CTX_set_cipher_list( ssl_context, "ALL:!ADH:!LOW:!EXP:!MD5:@STRENGTH" ) != 1 )
		return LIBIRC_ERR_SSL_INIT_FAILED;

	// Set the verification
	if ( session->options & LIBIRC_OPTION_SSL_NO_VERIFY )
		SSL_CTX_set_verify( ssl_context, SSL_VERIFY_NONE, 0 );
	else
		SSL_CTX_set_verify( ssl_context, SSL_VERIFY_PEER, 0 );
	
	// Disable session caching
	SSL_CTX_set_session_cache_mode( ssl_context, SSL_SESS_CACHE_OFF );

	// Enable SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER so we can move the buffer during sending
	SSL_CTX_set_mode( ssl_context, SSL_CTX_get_mode(ssl_context) | SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER | SSL_MODE_ENABLE_PARTIAL_WRITE );
	
	return 0;
}


#if defined (_WIN32)
	#define SSLINIT_LOCK_MUTEX(a)		WaitForSingleObject( a, INFINITE )
	#define SSLINIT_UNLOCK_MUTEX(a)		ReleaseMutex( a )
#else
	#define SSLINIT_LOCK_MUTEX(a)		pthread_mutex_lock( &a )
	#define SSLINIT_UNLOCK_MUTEX(a)		pthread_mutex_unlock( &a )
#endif

// Initializes the SSL context. Must be called after the socket is created.
static int ssl_init( irc_session_t * session )
{
	static int ssl_context_initialized = 0;
	
#if defined (_WIN32)
	static HANDLE initmutex = 0;
	
	// First time run? Create the mutex
	if ( initmutex == 0 )
	{ 
		HANDLE m = CreateMutex( 0, FALSE, 0 );

		// Now we check if the mutex has already been created by another thread performing the init concurrently.
		// If it was, we close our mutex and use the original one. This could be done synchronously by using the
		// InterlockedCompareExchangePointer function.
		if ( InterlockedCompareExchangePointer( &m, m, 0 ) != 0 )
			CloseHandle( m );
	}
#else
	static pthread_mutex_t initmutex = PTHREAD_MUTEX_INITIALIZER;
#endif
	
	// This initialization needs to be performed only once. The problem is that it is called from
	// irc_connect() and this function may be called simultaneously from different threads. So we have
	// to use mutex on Linux because it allows static mutex initialization. Windows doesn't, so here 
	// we do the sabre dance around it.
	SSLINIT_LOCK_MUTEX( initmutex );

	if ( ssl_context_initialized == 0 )
	{
		int res = ssl_init_context( session );
		
		if ( res )
		{
			SSLINIT_UNLOCK_MUTEX( initmutex );
			return res;
		}
		
		ssl_context_initialized = 1;
	}
	
	SSLINIT_UNLOCK_MUTEX( initmutex );
	
	// Get the SSL context
	session->ssl = SSL_new( ssl_context );

	if ( !session->ssl )
		return LIBIRC_ERR_SSL_INIT_FAILED;

	// Let OpenSSL use our socket
	if ( SSL_set_fd( session->ssl, session->sock) != 1 )
		return LIBIRC_ERR_SSL_INIT_FAILED;
	
	// Since we're connecting on our own, tell openssl about it
	SSL_set_connect_state( session->ssl );

	return 0;
}

static void ssl_handle_error( irc_session_t * session, int ssl_error )
{
	if ( ERR_GET_LIB(ssl_error) == ERR_LIB_SSL )
	{
		if ( ERR_GET_REASON(ssl_error) == SSL_R_CERTIFICATE_VERIFY_FAILED )
		{
			session->lasterror = LIBIRC_ERR_SSL_CERT_VERIFY_FAILED;
			return;
		}
		
		if ( ERR_GET_REASON(ssl_error) == SSL_R_UNKNOWN_PROTOCOL )
		{
			session->lasterror = LIBIRC_ERR_CONNECT_SSL_FAILED;
			return;
		}
	}

#if defined (ENABLE_DEBUG)
	if ( IS_DEBUG_ENABLED(session) )
		fprintf (stderr, "[DEBUG] SSL error: %s\n\t(%d, %d)\n", 
			 ERR_error_string( ssl_error, NULL),  ERR_GET_LIB( ssl_error), ERR_GET_REASON(ssl_error) );
#endif
}

static int ssl_recv( irc_session_t * session )
{
	int count;
	unsigned int amount = (sizeof (session->incoming_buf) - 1) - session->incoming_offset;
	
	ERR_clear_error();

	// Read up to m_bufferLength bytes
	count = SSL_read( session->ssl, session->incoming_buf + session->incoming_offset, amount );

    if ( count > 0 )
		return count;
	else if ( count == 0 )
		return -1; // remote connection closed
	else
	{
		int ssl_error = SSL_get_error( session->ssl, count );
		
		// Handle SSL error since not all of them are actually errors
        switch ( ssl_error )
        {
            case SSL_ERROR_WANT_READ:
                // This is not really an error. We received something, but
                // OpenSSL gave nothing to us because all it read was
                // internal data. Repeat the same read.
				return 0;

            case SSL_ERROR_WANT_WRITE:
                // This is not really an error. We received something, but
                // now OpenSSL needs to send the data before returning any
                // data to us (like negotiations). This means we'd need
                // to wait for WRITE event, but call SSL_read() again.
                session->flags |= SESSIONFL_SSL_READ_WANTS_WRITE;
				return 0;
		}

		// This is an SSL error, handle it
		ssl_handle_error( session, ERR_get_error() ); 
	}
	
	return -1;
}


static int ssl_send( irc_session_t * session )
{
	int count;
    ERR_clear_error();

	count = SSL_write( session->ssl, session->outgoing_buf, session->outgoing_offset );

    if ( count > 0 )
		return count;
    else if ( count == 0 )
		return -1;
    else
    {
		int ssl_error = SSL_get_error( session->ssl, count );
		
        switch ( ssl_error )
        {
            case SSL_ERROR_WANT_READ:
                // This is not really an error. We sent some internal OpenSSL data,
                // but now it needs to read more data before it can send anything.
                // Thus we wait for READ event, but will call SSL_write() again.
                session->flags |= SESSIONFL_SSL_WRITE_WANTS_READ;
				return 0;

           case SSL_ERROR_WANT_WRITE:
                // This is not really an error. We sent some data, but now OpenSSL
                // wants to send some internal data before sending ours.
                // Repeat the same write.
				return 0;
        }
        
		// This is an SSL error, handle it
		ssl_handle_error( session, ERR_get_error() ); 
    }

	return -1;
}

#endif


// Handles both SSL and non-SSL reads.
// Returns -1 in case there is an error and socket should be closed/connection terminated
// Returns 0 in case there is a temporary error and the call should be retried (SSL_WANTS_WRITE case)
// Returns a positive number if we actually read something
static int session_socket_read( irc_session_t * session )
{
	int length;

#if defined (ENABLE_SSL)
	if ( session->ssl )
	{
		// Yes, I know this is tricky
		if ( session->flags & SESSIONFL_SSL_READ_WANTS_WRITE )
		{
			session->flags &= ~SESSIONFL_SSL_READ_WANTS_WRITE;
			ssl_send( session );
			return 0;
		}
		
		return ssl_recv( session );
	}
#endif
	
	length = socket_recv( &session->sock, 
						session->incoming_buf + session->incoming_offset, 
					    (sizeof (session->incoming_buf) - 1) - session->incoming_offset );
	
	// There is no "retry" errors for regular sockets
	if ( length <= 0 )
		return -1;
	
	return length;
}

// Handles both SSL and non-SSL writes.
// Returns -1 in case there is an error and socket should be closed/connection terminated
// Returns 0 in case there is a temporary error and the call should be retried (SSL_WANTS_WRITE case)
// Returns a positive number if we actually sent something
static int session_socket_write( irc_session_t * session )
{
	int length;

#if defined (ENABLE_SSL)
	if ( session->ssl )
	{
		// Yep
		if ( session->flags & SESSIONFL_SSL_WRITE_WANTS_READ )
		{
			session->flags &= ~SESSIONFL_SSL_WRITE_WANTS_READ;
			ssl_recv( session );
			return 0;
		}
		
		return ssl_send( session );
	}
#endif
	
	length = socket_send (&session->sock, session->outgoing_buf, session->outgoing_offset);
	
	// There is no "retry" errors for regular sockets
	if ( length <= 0 )
		return -1;
	
	return length;
}
