local S = require'syscall'
local events = require'nodish.events'
local stream = require'nodish.stream'
local nextTick = require'nodish.nexttick'.nextTick
local util = require'nodish._util'
local ev = require'ev'
local buffer = require'nodish.buffer'
local octal = require "syscall.helpers".octal
local loop = ev.Loop.default

local createReadStream = function(path,options)
  options = options or {}
  local fd = options.fd
  local encoding = options.encoding
  local flags = options.flags or 'r'
  local autoClose
  if options.autoClose ~= nil then
    autoClose = options.autoClose
  else
    autoClose = true
  end
  local mode
  if options.mode then
    mode = octal(options.mode)
  else
    mode = octal('0666')
  end
  local self = events.EventEmitter()
  self.watchers = {}
  stream.readable(self)
  
  if not fd then
    local err
    fd,err = S.open(path,"rdonly",438)--mode)
    if not fd then
      error(err)
    end
  end
  local readable = true
  fd:nonblock(true)
  
  self.destroy = function(_,hadError)
    for _,watcher in pairs(self.watchers) do
      watcher:stop(loop)
    end
    if fd and autoClose then
      fd:close()
      fd = nil
      self:emit('close',hadError)
    end
  end
  
  self:once('error',function(err)
      local hadError = err and true
      self:destroy(hadError)
    end)
  
  self:once('fin',function()
      self:destroy(hadError)
    end)
  
  local buf
  local chunkSize = 4096*2
  
  self._read = function()
    if not buf or not buf:isReleased() then
      buf = buffer.Buffer(chunkSize)
    end
    local ret,err = fd:read(buf.buf,chunkSize)
    if ret then
      if ret > 0 then
        buf:_setLength(ret)
        assert(buf.length == ret)
        data = buf
        return data,err
      elseif ret == 0 then
        return nil,nil,true
      end
    end
    return nil,err
  end
  
  nextTick(function()
      self:emit('open',fd:getfd())
      self:addReadWatcher(fd:getfd())
      self:resume()
    end)
  
  return self
end

local readFile = function(path,callback)
  local rs = createReadStream(path)
  rs:on('error',function(err)
      callback(err)
    end)
  local content = ''
  rs:on('data',function(data)
      content = content..data:toString()
    end)
  rs:on('fin',function()
      callback(nil,content)
    end)
end

return {
  createReadStream = createReadStream,
  readFile = readFile,
}
