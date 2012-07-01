local namespace, channel, cursor, limit = ARGV[1], ARGV[2], ARGV[3], ARGV[4]
local channel_key = namespace .. ':channel:' .. channel

cursor = math.max(0, cursor) -- cursor can't be negative
limit = math.min(limit, 3999) -- 3999 is the limit of unpack()

-- for results from multiple channels, we'll merge them into a single set
local union_key
if string.find(channel_key, '*') then
  local matched_keys = redis.call('keys', channel_key)
  -- the pattern matched multiple keys, we have to merge the keys
  -- we could use zunionstore here, but it wouldn't be optimal for very large sets
  if #matched_keys > 1 then
    union_key = channel_key .. '@' .. redis.call('get', namespace .. ':id')
    for i,key in ipairs(matched_keys) do
      local msgs_ids = redis.call('zrangebyscore', key, '(' .. cursor, '+inf', 'WITHSCORES', 'LIMIT', 0, limit)
      if #msgs_ids > 0 then
        -- `zadd` takes scores first, so we have to reverse
        local len, reversed = #msgs_ids, {}
        for i = len, 1, -1 do reversed[len - i + 1] = msgs_ids[i] end
        redis.call('zadd', union_key, unpack(reversed))
      end
    end
    channel_key = union_key
  else
    channel_key = matched_keys[1]
  end
end

-- as long as we have a channel key, get the messages and add wrap with them with ids
local msgs = {}
if channel_key ~= nil then
  msgs = redis.call('zrangebyscore', channel_key, '(' .. cursor, '+inf', 'WITHSCORES', 'LIMIT', 0, limit)
end

-- if we've merged multiple channels, remove the union key
if union_key ~= nil then
  redis.call('del', union_key)
end

return msgs