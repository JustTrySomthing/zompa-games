-- Length-prefixed primitives keep saves data-only, including sparse lock tables.
local S={}
function S.encode(v)
    if type(v)=="table" then
        local out={"{"}
        for k,item in pairs(v) do
            out[#out+1]=S.encode(k);out[#out+1]=S.encode(item)
        end
        return table.concat(out).."}"
    end
    local raw=tostring(v)
    return (type(v)=="number" and "n" or "s")..#raw..":"..raw
end
function S.decode(data)
    local pos=1
    local function read(depth)
        assert(depth<16 and pos<=#data)
        local marker=data:sub(pos,pos);pos=pos+1
        if marker=="{" then
            local t={}
            while data:sub(pos,pos)~="}" do local k=read(depth+1);t[k]=read(depth+1) end
            pos=pos+1;return t
        end
        assert(marker=="n" or marker=="s")
        local stop=assert(data:find(":",pos,true))
        local len=assert(tonumber(data:sub(pos,stop-1)))
        assert(len>=0 and len%1==0 and stop+len<=#data)
        local value=data:sub(stop+1,stop+len);pos=stop+len+1
        if marker=="n" then return assert(tonumber(value)) end
        return value
    end
    local value=read(0);assert(pos==#data+1);return value
end
return S
