--

require "lpeg"

local P, S, R = lpeg.P, lpeg.S, lpeg.R
local C, Cg, Ct = lpeg.C, lpeg.Cg, lpeg.Ct

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
local parameter = Cg(attribute, 'name') * P"=" * Cg(value, 'value')

local parameters = (P";" * Ct(parameter))^0
local media_type = C(token) * P"/" * C(token) * parameters
local media_types = media_type * (spacing * P"," * spacing * media_type)^0

-- Parses a mime-type into its component parts.
local _parse_mime_type = Ct(media_type) * P(-1)
function parse_mime_type(mime_type)
	return _parse_mime_type:match(mime_type)
end

-- Media-ranges are mime-types with wild-cards and a 'q' quality parameter.
function parse_media_range(media_range)
	return parse_mime_type(media_range)
end

-- Determines the quality ('q') of a mime-type when compared against a list
-- of media-ranges.
function quality()
end

-- Just like quality() except the second parameter must be pre-parsed.
function quality_parsed()
end

-- Just like quality_parsed() but also returns the fitness score.
function fitness_and_quality_parsed()
end

-- Choose the mime-type with the highest fitness score and quality ('q')
-- from a list of candidates.
function best_match()
end
