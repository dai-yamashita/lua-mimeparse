--
-- This module provides basic functions for handling mime-types. It can
-- handle matching mime-types against a list of media-ranges. See section
-- 14.1 of the HTTP specification [RFC 2616] for a complete explanation.
--
--   http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.1
--
-- A port to Lua/Lpeg of Joe Gregorio's MIME-Type Parser:
--
--   http://code.google.com/p/mimeparse/
--
-- Ported by Alejandro Mery <amery@geeks.cl> from version 0.1.3
-- Comments are mostly excerpted from the original.

require "lpeg"

local P, S, R = lpeg.P, lpeg.S, lpeg.R
local C, Cg, Ct = lpeg.C, lpeg.Cg, lpeg.Ct

local ipairs, pairs, tonumber = ipairs, pairs, tonumber
local tsort = table.sort

module (...)

--[[
media-type     = type "/" subtype *( ";" parameter )
parameter      = attribute "=" value
attribute      = token
value          = token | quoted-string
quoted-string  = ( <"> *(qdtext | quoted-pair ) <"> )
qdtext         = <any TEXT except <">>
quoted-pair    = "\" CHAR
type           = token
subtype        = token
token          = 1*<any CHAR except CTLs or separators>
CHAR           = <any US-ASCII character (octets 0 - 127)>
separators     = "(" | ")" | "<" | ">" | "@"
               | "," | ";" | ":" | "\" | <">
               | "/" | "[" | "]" | "?" | "="
               | "{" | "}" | SP | HT
CTL            = <any US-ASCII ctl chr (0-31) and DEL (127)>
]]--
local CTL = R"\0\31" + P"\127"
local CHAR = R"\0\127"
local quote = P'"'
local separators = S"()<>@,;:\\\"/[]?={} \t"
local token = (CHAR - CTL - separators)^1
local spacing = (S" \t")^0

local qdtext = P(1) - CTL - quote
local quoted_pair = P"\\" * CHAR
local quoted_string = quote * C((qdtext + quoted_pair)^0) * quote

local attribute = C(token)
local value = C(token) + quoted_string
local parameter = attribute * P"=" * value

local function foldparams(...)
	local params = {}
	local key
	for _, v in ipairs{...} do
		if key then
			params[key] = v
			key = nil
		else
			key = v
		end
	end
	return params
end

local parameters = (spacing * P";" * spacing * parameter)^0
-- TODO: support "*" as alias of "*/*" as Joe Gregorio's
local media_type = Ct(C(token) * P"/" * C(token) * (parameters/foldparams))
local media_ranges = media_type * (spacing * P"," * spacing * media_type)^0

-- Parses a mime-type into its component parts.
local _parse_mime_type = media_type * P(-1)
function parse_mime_type(mime_type)
--[[
	Carves up a mime-type and returns a tuple of the
	(type, subtype, params) where 'params' is a dictionary
	of all the parameters for the media range.
	For example, the media range 'application/xhtml;q=0.5' would
	get parsed into:

	{'application', 'xhtml', {'q' = '0.5'}}
	]]--
	return _parse_mime_type:match(mime_type)
end

-- Media-ranges are mime-types with wild-cards and a 'q' quality parameter.
function parse_media_range(media_range)
--[[
	Carves up a media range and returns a tuple of the
	(type, subtype, params) where 'params' is a dictionary
	of all the parameters for the media range.
	For example, the media range 'application/*;q=0.5' would
	get parsed into:

	{'application', '*', {'q' = '0.5'}}

	In addition this function also guarantees that there
	is a value for 'q' in the params dictionary, filling it
	in with a proper default if necessary.
	]]--
	local r = parse_mime_type(media_range)
	if r then
		local q = tonumber(r[3]["q"]) or 1
		if q < 0 or q > 1 then
			q = 1
		end
		r[3]["q"] = q
	end
	return r
end

-- same as parse_media_range for a comma delimited list
local _parse_media_ranges = Ct(media_ranges) * P(-1)
function parse_media_ranges(ranges)
--[[
	]]--
	local t = _parse_media_ranges:match(ranges)
	if t then
		for _, r in ipairs(t) do
			local q = tonumber(r[3]["q"]) or 1
			if q < 0 or q > 1 then
				q = 1
			end
			r[3]["q"] = q
		end
	end
	return t
end

-- Just like quality_parsed() but also returns the fitness score.
function fitness_and_quality_parsed(mime_type, parsed_ranges)
--[[
	Find the best match for a given mime-type against
	a list of media_ranges that have already been
	parsed by parse_media_range(). Returns a tuple of
	the fitness value and the value of the 'q' quality
	parameter of the best match, or {-1, 0} if no match
	was found. Just as for quality_parsed(), 'parsed_ranges'
	must be a list of parsed media ranges.
	]]--
	local best_fitness = -1
	local best_fit_q = 0

	local t = parse_media_range(mime_type)
	if t and parsed_ranges then
		for _,r in ipairs(parsed_ranges) do
			if (r[1] == t[1] or r[1] == "*" or t[1] == "*") and
			   (r[2] == t[2] or r[2] == "*" or t[2] == "*") then

				local fitness = (r[1] == t[1]) and 100 or 0
				fitness = fitness + ((r[2] == t[2]) and 10 or 0)

				for k,v in pairs(t[3]) do
					if k ~= 'q' and r[3][k] == t[3][k] then
						fitness = fitness + 1
					end
				end
				if fitness > best_fitness then
					best_fitness = fitness
					best_fit_q = r[3]["q"]
				end
			end
		end
	end

	return best_fitness, best_fit_q
end

-- Just like quality() except the second parameter must be pre-parsed.
function quality_parsed(mime_type, parsed_ranges)
--[[
	Find the best match for a given mime-type against
	a list of media_ranges that have already been
	parsed by parse_media_range(). Returns the
	'q' quality parameter of the best match, 0 if no
	match was found. This function bahaves the same as quality()
	except that 'parsed_ranges' must be a list of
	parsed media ranges.
	]]--

	local _, q = fitness_and_quality_parsed(mime_type, parsed_ranges)
	return q
end

-- Determines the quality ('q') of a mime-type when compared against a list
-- of media-ranges.
function quality(mime_type, ranges)
--[[
	Returns the quality 'q' of a mime-type when compared
	against the media-ranges in ranges. For example:

	>>> quality('text/html','text/*;q=0.3, text/html;q=0.7, text/html;level=1, text/html;level=2;q=0.4, */*;q=0.5')
	0.7
	]]--
	local parsed_ranges = parse_media_ranges(ranges)
	return quality_parsed(mime_type, parsed_ranges)
end

-- Choose the mime-type with the highest fitness score and quality ('q')
-- from a list of candidates.
local function best_match_comp(a,b)
	for i = 1,3 do
		local comp = a[i] - b[i]
		if comp > 0 then
			return true
		elseif comp < 0 then
			return
		end
	end
end

function best_match(supported, header)
--[[
	Takes a list of supported mime-types and finds the best
	match for all the media-ranges listed in header. The value of
	header must be a string that conforms to the format of the
	HTTP Accept: header. The value of 'supported' is a list of
	mime-types. The list of supported mime-types should be sorted
	in order of increasing desirability, in case of a situation
	where there is a tie

	>>> best_match({'application/xbel+xml', 'text/xml'}, 'text/*;q=0.5,*/*; q=0.1')
	'text/xml'
	]]--
	local parsed_header = parse_media_ranges(header)
	local matches = {}

	for pos, mime_type in ipairs(supported) do
		local f,q = fitness_and_quality_parsed(mime_type, parsed_header)
		matches[#matches+1] = {f, q, pos, mime_type}
	end

	tsort(matches, best_match_comp)

	return (matches[1][2] ~= 0) and matches[1][4] or ""
end
