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

#include <ctype.h>

#define LIBIRC_COLORPARSER_BOLD			(1<<1)
#define LIBIRC_COLORPARSER_UNDERLINE	(1<<2)
#define LIBIRC_COLORPARSER_REVERSE		(1<<3)
#define LIBIRC_COLORPARSER_COLOR		(1<<4)

#define LIBIRC_COLORPARSER_MAXCOLORS	15


static const char * color_replacement_table[] =
{
	"WHITE",
	"BLACK",
	"DARKBLUE",
	"DARKGREEN",
	"RED",
	"BROWN",
	"PURPLE",
	"OLIVE",
	"YELLOW",
	"GREEN",
	"TEAL",
	"CYAN",
	"BLUE",
	"MAGENTA",
	"DARKGRAY",
	"LIGHTGRAY",
	0
};


static inline void libirc_colorparser_addorcat (char ** destline, unsigned int * destlen, const char * str)
{
	unsigned int len = strlen(str);

	if ( *destline )
	{
		strcpy (*destline, str);
		*destline += len;
	}
	else
		*destlen += len;
}


static void libirc_colorparser_applymask (unsigned int * mask, 
		char ** destline, unsigned int * destlen,
		unsigned int bitmask, const char * start, const char * end)
{
	if ( (*mask & bitmask) != 0 )
	{
		*mask &= ~bitmask;
		libirc_colorparser_addorcat (destline, destlen, end);
	}
	else
	{
		*mask |= bitmask;
		libirc_colorparser_addorcat (destline, destlen, start);
	}
}


static void libirc_colorparser_applycolor (unsigned int * mask, 
		char ** destline, unsigned int * destlen,
		unsigned int colorid, unsigned int bgcolorid)
{
	const char * end = "[/COLOR]";
	char startbuf[64];

	if ( bgcolorid != 0 )
		sprintf (startbuf, "[COLOR=%s/%s]", color_replacement_table[colorid], color_replacement_table[bgcolorid]);
	else
		sprintf (startbuf, "[COLOR=%s]", color_replacement_table[colorid]);

	if ( (*mask & LIBIRC_COLORPARSER_COLOR) != 0 )
		libirc_colorparser_addorcat (destline, destlen, end);

	*mask |= LIBIRC_COLORPARSER_COLOR;
	libirc_colorparser_addorcat (destline, destlen, startbuf);
}


static void libirc_colorparser_closetags (unsigned int * mask, 
		char ** destline, unsigned int * destlen)
{
	if ( *mask & LIBIRC_COLORPARSER_BOLD )
		libirc_colorparser_applymask (mask, destline, destlen, LIBIRC_COLORPARSER_BOLD, 0, "[/B]");

	if ( *mask & LIBIRC_COLORPARSER_UNDERLINE )
		libirc_colorparser_applymask (mask, destline, destlen, LIBIRC_COLORPARSER_UNDERLINE, 0, "[/U]");

	if ( *mask & LIBIRC_COLORPARSER_REVERSE )
		libirc_colorparser_applymask (mask, destline, destlen, LIBIRC_COLORPARSER_REVERSE, 0, "[/I]");

	if ( *mask & LIBIRC_COLORPARSER_COLOR )
		libirc_colorparser_applymask (mask, destline, destlen, LIBIRC_COLORPARSER_COLOR, 0, "[/COLOR]");
}



/*
 * IRC to [code] color conversion. Or strip.
 */
static char * libirc_colorparser_irc2code (const char * source, int strip)
{
	unsigned int mask = 0, destlen = 0;
	char * destline = 0, *d = 0;
	const char *p;
	int current_bg = 0;

    /*
     * There will be two passes. First pass calculates the total length of
     * the destination string. The second pass allocates memory for the string,
     * and fills it.
     */
	while ( destline == 0 ) // destline will be set after the 2nd pass
	{
		if ( destlen > 0 )
		{
			// This is the 2nd pass; allocate memory.
			if ( (destline = (char*)malloc (destlen)) == 0 )
				return 0;

			d = destline;
		}

		for ( p = source; *p; p++ )
		{
			switch (*p)
			{
			case 0x02:	// bold
				if ( strip )
					continue;

				libirc_colorparser_applymask (&mask, &d, &destlen, LIBIRC_COLORPARSER_BOLD, "[B]", "[/B]");
				break;
				
			case 0x1F:	// underline
				if ( strip )
					continue;

				libirc_colorparser_applymask (&mask, &d, &destlen, LIBIRC_COLORPARSER_UNDERLINE, "[U]", "[/U]");
				break;

			case 0x16:	// reverse
				if ( strip )
					continue;

				libirc_colorparser_applymask (&mask, &d, &destlen, LIBIRC_COLORPARSER_REVERSE, "[I]", "[/I]");
				break;

			case 0x0F:	// reset colors
				if ( strip )
					continue;

				libirc_colorparser_closetags (&mask, &d, &destlen);
				break;

			case 0x03:	// set color
				if ( isdigit (p[1]) )
				{
					// Parse 
					int bgcolor = -1, color = p[1] - 0x30;
					p++;

					if ( isdigit (p[1]) )
					{
						color = color * 10 + (p[1] - 0x30);
						p++;
					}

					// If there is a comma, search for the following 
					// background color
					if ( p[1] == ',' && isdigit (p[2]) )
					{
						bgcolor = p[2] - 0x30;
						p += 2;

						if ( isdigit (p[1]) )
						{
							bgcolor = bgcolor * 10 + (p[1] - 0x30);
							p++;
						}
					}

					// Check for range
					if ( color <= LIBIRC_COLORPARSER_MAXCOLORS 
					&& bgcolor <= LIBIRC_COLORPARSER_MAXCOLORS )
					{
						if ( strip )
							continue;

						if ( bgcolor != -1 )
							current_bg = bgcolor;

						libirc_colorparser_applycolor (&mask, &d, &destlen, color, current_bg);
					}
				}
				break;

			default:
				if ( destline )
					*d++ = *p;
				else
					destlen++;
				break;
			}
		}

		// Close all the opened tags
		libirc_colorparser_closetags (&mask, &d, &destlen);
		destlen++; // for 0-terminator
	}

	*d = '\0';
	return destline;
}


static int libirc_colorparser_colorlookup (const char * color)
{
	int i;
	for ( i = 0; color_replacement_table[i]; i++ )
		if ( !strcmp (color, color_replacement_table[i]) )
			return i;

	return -1;
}


/*
 * [code] to IRC color conversion.
 */
char * irc_color_convert_to_mirc (const char * source)
{
	unsigned int destlen = 0;
	char * destline = 0, *d = 0;
	const char *p1, *p2, *cur;

    /*
     * There will be two passes. First pass calculates the total length of
     * the destination string. The second pass allocates memory for the string,
     * and fills it.
     */
	while ( destline == 0 ) // destline will be set after the 2nd pass
	{
		if ( destlen > 0 )
		{
			// This is the 2nd pass; allocate memory.
			if ( (destline = (char*)malloc (destlen)) == 0 )
				return 0;

			d = destline;
		}

		cur = source;
		while ( (p1 = strchr (cur, '[')) != 0 )
		{
			const char * replacedval = 0;
			p2 = 0;

			// Check if the closing bracket is available after p1
			// and the tag length is suitable
			if ( p1[1] != '\0' 
			&& (p2 = strchr (p1, ']')) != 0
			&& (p2 - p1) > 1
			&& (p2 - p1) < 31 )
			{
				// Get the tag
				char tagbuf[32];
				int taglen = p2 - p1 - 1;

				memcpy (tagbuf, p1 + 1, taglen);
				tagbuf[taglen] = '\0';

				if ( !strcmp (tagbuf, "/COLOR") )
					replacedval = "\x0F";
				else if ( strstr (tagbuf, "COLOR=") == tagbuf )
				{
					int color, bgcolor = -2;
					char * bcol;

					bcol = strchr (tagbuf + 6, '/');

					if ( bcol )
					{
						*bcol++ = '\0';
						bgcolor = libirc_colorparser_colorlookup (bcol);
					}

					color = libirc_colorparser_colorlookup (tagbuf + 6);

					if ( color != -1 && bgcolor == -2 )
					{
						sprintf (tagbuf, "\x03%02d", color);
						replacedval = tagbuf;
					}
					else if ( color != -1 && bgcolor >= 0 )
					{
						sprintf (tagbuf, "\x03%02d,%02d", color, bgcolor);
						replacedval = tagbuf;
					}
				}
				else if ( !strcmp (tagbuf, "B") || !strcmp (tagbuf, "/B") )
					replacedval = "\x02";
				else if ( !strcmp (tagbuf, "U") || !strcmp (tagbuf, "/U") )
					replacedval = "\x1F";
				else if ( !strcmp (tagbuf, "I") || !strcmp (tagbuf, "/I") )
					replacedval = "\x16";
			}

			if ( replacedval )
			{
				// add a part before the tag
				int partlen = p1 - cur;

				if ( destline )
				{
					memcpy (d, cur, partlen);
					d += partlen;
				}
				else
					destlen += partlen;

				// Add the replacement
				libirc_colorparser_addorcat (&d, &destlen, replacedval);

				// And move the pointer
				cur = p2 + 1;
			}
			else
			{
				// add a whole part before the end tag
				int partlen;

				if ( !p2 )
					p2 = cur + strlen(cur);

				partlen = p2 - cur + 1;

				if ( destline )
				{
					memcpy (d, cur, partlen);
					d += partlen;
				}
				else
					destlen += partlen;

				// And move the pointer
				cur = p2 + 1;
			}
		}

		// Add the rest of string
		libirc_colorparser_addorcat (&d, &destlen, cur);
		destlen++; // for 0-terminator
	}

	*d = '\0';
	return destline;
}


char * irc_color_strip_from_mirc (const char * message)
{
	return libirc_colorparser_irc2code (message, 1);
}


char * irc_color_convert_from_mirc (const char * message)
{
	return libirc_colorparser_irc2code (message, 0);
}
