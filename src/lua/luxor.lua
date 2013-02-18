-- Luxor, a non-validating namespace aware xml parser
-- Requires lpeg, slnunicode

-- TODO:
--  * xinclude


local P,S = lpeg.P, lpeg.S

local string = unicode.utf8
local current_element


local function decode_xmlstring( txt )
	txt = string.gsub(txt,"&#(%d+);",string.char)
	txt = string.gsub(txt,"&#x(%x+);",function(num) return string.char(tonumber(num,16)) end)
	txt = string.gsub(txt,"&(.-);",{lt = "<",gt = ">", amp = "&", quot = '"', apos = "'"})
	return txt
end

local function _att_value( ... )
	return decode_xmlstring(select(1,...))
end

local function _attribute( ... )
	current_element[select(1,...)] = select(2,...)
end

local quote = P'"'
local apos  = P"'"
local non_att_quote = P( 1 - quote)^1
local non_att_apos  = P( 1 - apos)^1
local space = S("\09\010\013\032")^1
local name = P(1 - ( space + "="))^1
local att_value = ( quote * lpeg.C(non_att_quote) * quote + apos * lpeg.C(non_att_apos) * apos ) / _att_value
local attrib = (space^-1 * lpeg.C(name) * space^-1 * P"=" * space^-1 * att_value) / _attribute
local attributes = attrib^0 * space^-1

local function xml_to_string( self )
  local ret = {}
  for i=1,#self do
    ret[#ret + 1] = tostring(self[i])
  end
  return table.concat(ret)
end

local mt = {
  __tostring = xml_to_string
}

local function read_attributes(txt,pos,namespaces)
	current_element = setmetatable({[".__ns"] = {}},mt)
	local ns,prefix
	ns = current_element[".__ns"]
	for k,v in pairs(namespaces) do
		ns[k] = v
	end
	pos = lpeg.match(attributes,txt,pos)
	for k,v in pairs(current_element) do
		if string.match(k,"^xmlns$") then
			ns[".__default"] = v
			current_element[k] = nil
		end
		prefix = string.match(k,"^xmlns:(.*)")
		if prefix then
			ns[prefix] = v
			current_element[k] = nil
		end
	end
	current_element[".__type"]="element"
	return pos, current_element
end

local function parse_xmldecl( txt,pos )
	local newpos = string.find(txt,"<",pos+1)
	return newpos
end
local function parse_comment( txt,pos )
	local _,newpos,contents = string.find(txt,"%-(.-)%-%->",pos+3)
	-- return {[".__type"]="comment",contents},newpos
	return "",newpos
end
local function parse_pi(txt,pos)
	local _,newpos,contents = string.find(txt,"<%?(.-)%?>",pos)
	return {[".__type"]="pi", contents },newpos
end
local function parse_cdata( txt,pos )
	local _,newpos,contents = string.find(txt,"<!%[CDATA%[(.-)%]%]>",pos)
	return contents,newpos
end

local function parse_endelement( txt,pos )
	local endpos = string.find(txt,">",pos)
	return endpos
end

local function parse_element( txt,pos,namespaces )
	local second_nextchar
	local contents
	local _,_,nextchar = string.find(txt,"(.)",pos+1)
	if nextchar == "!" then
		_,_,second_nextchar = string.find(txt,"(.)",pos+2)
		if second_nextchar=="-" then
			-- exclam hyphen -> comment
			return parse_comment(txt,pos)
		else
			return parse_cdata(txt,pos)
		end
	elseif nextchar == "/" then -- </endelement
		pos = parse_endelement(txt,pos)
		return nil,pos
		-- end element 
	elseif nextchar == "?" then
		return parse_pi(txt,pos)
	else
		local elt,eltname,namespace,local_name,ns
		_,pos,eltname = string.find(txt,"([^/>%s]+)",pos + 1)
		pos, elt = read_attributes(txt,pos + 1,namespaces)
		_,_,namespace,local_name = string.find(eltname,"^(.-):(.*)$")
		ns = elt[".__ns"]
		if namespace then
			if ns and ns[namespace] then
				elt[".__namespace"] = ns[namespace]
				elt[".__local_name"] = local_name
			else
				print("unknown namespace!!!")
			end
		else
			if ns then
				elt[".__namespace"] = ns[".__default"]
			end
			elt[".__local_name"] = eltname
		end
		elt[".__name"] = eltname
		-- We're now at the end of attributes. Get a /> or > now
		local rangle,pre_rangle
		_,rangle = string.find(txt,">",pos)
		_,_,pre_rangle = string.find(txt,"(.)",rangle - 1)
		if pre_rangle == "/" then
			return elt,rangle + 1
		end
		pos = rangle
		-- "Regular" (non-empty) element. Now parse it
		local start, stop, contents
		while true do
			start, stop = string.find(txt,"<",pos)
			contents = string.match(txt,"(.-)<",pos + 1)
			if contents ~= "" then
				if type(elt[#elt]) == "string" then
					elt[#elt] = elt[#elt] .. decode_xmlstring(contents)
				else
					elt[#elt + 1] = decode_xmlstring(contents)
				end
			end
			contents, pos = parse_element(txt,start,elt[".__ns"])
			if contents then
				if type(contents) == "string" then
					if contents ~= "" then
						if type(elt[#elt]) == "string" then
							elt[#elt] = elt[#elt] .. decode_xmlstring(contents)
						else
							elt[#elt + 1] = decode_xmlstring(contents)
						end
					end
				else
					elt[#elt + 1] = contents
					contents[".__parent"] = elt
				end
			else
				return elt,pos
			end
		end
	end
end

local function parse_xml(txt)
	local pos = 1
	local line = 1
	if string.byte(txt) ~= 60 then
		_,_,txt = string.find(txt,"(<.*)$",pos)
	end
	txt = txt.gsub(txt,"\13\n?","\n")
	if string.match(txt,"<%?xml",pos) then
		pos = parse_xmldecl(txt,pos)
	end
	local ret = parse_element(txt,pos,{})
	return ret
end

local function parse_xml_file( path )
  local xmlfile = io.open(path,"r")
  if not xmlfile then
    err("Can't open XML file. Abort.")
    os.exit(-1)
  end
  local text = xmlfile:read("*all")
  xmlfile:close()
  return parse_xml(text)
end


return {
	parse_xml = parse_xml,
	parse_xml_file = parse_xml_file,
}
