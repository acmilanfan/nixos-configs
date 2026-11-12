-- Real isolated filesystem tests; no browser, helper, account or live log access.
local source=debug.getinfo(1,"S").source:sub(2)
local root=source:match("^(.*)/tests/[^/]+$")
local function run()
    assert(hs.fs.attributes(root.."/youtube-capture-log.lua"),"persistent capture logger is missing")
    local logging=assert(loadfile(root.."/youtube-capture-log.lua"))()
    local base=os.getenv("HOME").."/ai/artifacts/org/youtube-direct-capture"
    local dir=base.."/logging-fixture-"..hs.host.uuid()
    assert(hs.fs.mkdir(dir))
    local console={}
    local function fresh(name, limit)
        return logging.new({hs=hs,directory=dir.."/"..name,maxBytes=limit or 2*1024*1024,
            console=function(line)console[#console+1]=line end})
    end
    local function read(path)
        local file=assert(io.open(path,"rb"));local text=file:read("*a");file:close();return text
    end
    local tests={}
    function tests.full_error_and_console()
        local log=fresh("full")
        local long=string.rep("detail ",100).."END OF ERROR"
        assert(log.record("helper_result",{code=7,stdout=hs.json.encode({error=long,items={}}),stderr="full stderr"}))
        local content=read(log.path)
        local event=hs.json.decode(content)
        assert(event.event=="helper_result" and event.code==7 and event.stderr=="full stderr")
        assert(hs.json.decode(event.stdout).error==long and event.time)
        assert(console[#console]:find("END OF ERROR",1,true))
        assert(hs.fs.attributes(log.path,"permissions")=="rw-------")
        assert(hs.fs.attributes(dir.."/full","permissions")=="rwx------")
    end
    function tests.credentials_are_redacted_in_both_sinks()
        local log=fresh("redacted")
        assert(log.record("helper_result",{code=1,stdout=hs.json.encode({error="invalid_grant: Token has expired or been revoked",nested={access_token="ACCESS_FIXTURE",refresh_token="REFRESH_FIXTURE",client_secret="CLIENT_FIXTURE",id_token="ID_FIXTURE",password="PASSWORD_FIXTURE"}}),
            stderr='safe first line\nAuthorization: Bearer BEARER_FIXTURE\nclient_secret=QUERY_FIXTURE\nhttps://example.org/?key=KEY_FIXTURE\nsecret=SECRET_FIXTURE\nsafe last line'}))
        for _,text in ipairs({read(log.path),console[#console]}) do
            for _,secret in ipairs({"ACCESS_FIXTURE","REFRESH_FIXTURE","CLIENT_FIXTURE","ID_FIXTURE","PASSWORD_FIXTURE","BEARER_FIXTURE","QUERY_FIXTURE","KEY_FIXTURE","SECRET_FIXTURE"}) do
                assert(not text:find(secret,1,true),"credential leaked: "..secret)
            end
            assert(text:find("invalid_grant",1,true) and text:find("safe last line",1,true))
        end
    end
    function tests.malformed_output_is_fail_closed()
        local log=fresh("malformed")
        assert(log.record("helper_result",{stdout='{"access_token":"BROKEN_FIXTURE",',stderr="Bearer BARE_FIXTURE"}))
        assert(not read(log.path):find("BROKEN_FIXTURE",1,true))
        assert(not console[#console]:find("BARE_FIXTURE",1,true))
    end
    function tests.malformed_json_cannot_hide_escaped_credential_fields()
        local log=fresh("malformed-escaped")
        assert(log.record("helper_result",{stdout='{"access\\u005ftoken":"ESCAPED_FIXTURE",'}))
        assert(not read(log.path):find("ESCAPED_FIXTURE",1,true))
        assert(not console[#console]:find("ESCAPED_FIXTURE",1,true))
    end
    function tests.escaped_credentials_in_arrays_and_fragments_are_redacted()
        for index,text in ipairs({
            'Response: {"access\\u005ftoken":"FRAGMENT_FIXTURE"}',
            '[{"access\\u005ftoken":"FRAGMENT_FIXTURE"}]',
            hs.json.encode({error='Response: {"refresh\\u005ftoken":"FRAGMENT_FIXTURE"}'}),
            '[{"access\\u005ftoken":"FRAGMENT_FIXTURE"},',
        }) do
            local log=fresh("fragment-"..index)
            assert(log.record("helper_result",{stdout=text,stderr=text}))
            assert(not read(log.path):find("FRAGMENT_FIXTURE",1,true),"escaped fragment leaked to disk")
            assert(not console[#console]:find("FRAGMENT_FIXTURE",1,true),"escaped fragment leaked to Console")
        end
    end
    function tests.private_key_blocks_are_not_retained()
        local text="safe first\n-----BEGIN PRIVATE KEY-----\nPRIVATE_BODY_FIXTURE\n-----END PRIVATE KEY-----\nsafe last"
        local clean=logging.redact(text)
        assert(not clean:find("PRIVATE_BODY_FIXTURE",1,true))
        assert(clean:find("safe first",1,true) and clean:find("safe last",1,true))
    end
    function tests.rotation_keeps_previous_event()
        local log=fresh("rotate",100)
        assert(log.record("notice",{message=string.rep("a",120)}))
        assert(log.record("notice",{message="second"}))
        assert(read(log.path):find("second",1,true))
        assert(read(log.path..".1"):find(string.rep("a",120),1,true))
        assert(hs.fs.attributes(log.path..".1","permissions")=="rw-------")
    end
    function tests.unsafe_targets_warn_without_overwriting()
        local victim=dir.."/victim"
        local file=assert(io.open(victim,"w"));file:write("preserve me");file:close()
        for _,kind in ipairs({"directory","file","rotation"}) do
            local log=fresh("unsafe-"..kind,1)
            if kind=="directory" then assert(hs.fs.link(dir,dir.."/unsafe-"..kind,true))
            else
                assert(hs.fs.mkdir(dir.."/unsafe-"..kind))
                assert(hs.fs.link(victim,log.path..(kind=="rotation" and ".1" or ""),true))
            end
            assert(log.record("notice",{message="never overwrite"})==false)
            assert(read(victim)=="preserve me")
        end
    end
    function tests.unwritable_directory_still_reaches_console()
        local log=logging.new({hs=hs,directory=dir.."/absent/parent/log",console=function(line)console[#console+1]=line end})
        -- A regular file cannot serve as the log directory.
        local file=assert(io.open(dir.."/blocked","w"));file:write("unchanged");file:close()
        log=logging.new({hs=hs,directory=dir.."/blocked",console=function(line)console[#console+1]=line end})
        assert(log.record("notice",{message="still in Console"})==false)
        assert(console[#console-1]:find("still in Console",1,true))
        assert(read(dir.."/blocked")=="unchanged")
    end
    local count,failures=0,{}
    for name,test in pairs(tests) do
        local ok,err=xpcall(test,debug.traceback)
        if not ok then failures[#failures+1]=name..": "..tostring(err) end
        count=count+1
    end
    assert(#failures==0,table.concat(failures,"\n"))
    print("PASS: youtube capture logging ("..count.." cases); fixtures: "..dir)
end
local ok,err=xpcall(run,debug.traceback)
if not ok then print("FAIL: youtube capture logging\n"..tostring(err)) end
