local loaded = {}
local _require = require

package = {
    path = './?.lua;./?/init.lua',
    preload = {},
    loaded = setmetatable({}, {
        __index = loaded,
        __newindex = noop,
        __metatable = false,
    })
}

---@param modName string
---@return string
---@return string
local function getModuleInfo(modName)
    local resourceSrc

    if not modName:find('^@') then
        local idx = 1

        while true do
            local di = debug.getinfo(idx, 'S')

            if di then
                if not di.short_src ~= '?' and di.source:match('^@([^%s]+)') and not di.short_src:find('^@ox_lib/imports/require') and not di.short_src:find('^citizen') then
                    resourceSrc = di.source:gsub('^%@+([^/]+)/.+', '%1')
                    break
                end
            else
                resourceSrc = cache.resource
                break
            end

            idx += 1
        end
    else
        resourceSrc = modName:gsub('^@(.-)/.+', '%1')
        modName = modName:sub(#resourceSrc + 3)
    end

    return resourceSrc, modName
end

local tempData = {}

---@param name string
---@param path string
---@return string? filename
---@return string? errmsg
function package.searchpath(name, path)
    local resourceSrc, modName = getModuleInfo(name:gsub('%.', '/'))
    local tried = {}

    for template in path:gmatch('[^;]+') do
        local fileName = template:gsub('^%./', ''):gsub('?', modName:gsub('%.', '/') or modName)
        local file = LoadResourceFile(resourceSrc, fileName)

        if file then
            tempData[1] = file
            tempData[2] = resourceSrc
            return fileName
        end

        tried[#tried + 1] = fileName
    end

    return nil, table.concat(tried, "\n\t")
end

---Attempts to load a module at the given path relative to the resource root directory.\
---Returns a function to load the module chunk, or a string containing all tested paths.
---@param modName string
---@param env? table
local function loadModule(modName, env)
    local fileName, err = package.searchpath(modName, package.path)

    if fileName then
        local file = tempData[1]
        local resource = tempData[2]

        table.wipe(tempData)
        return assert(load(file, ('@@%s/%s'):format(resource, modName), 't', env or _ENV))
    end

    return nil, err or 'unknown error'
end

package.searchers = {
    function(modName) return package.preload[modName] end,
    function(modName)
        local ok, result = pcall(_require, modName)

        if ok then return result end

        return ok, result
    end,
    function(modName) return loadModule(modName) end,
}

---@param filePath string
---@param env? table
---@return unknown
---Loads and runs a Lua file at the given path. Unlike require, the chunk is not cached for future use.
function lib.load(filePath, env)
    if type(filePath) ~= 'string' then
        error(("file path must be a string (received '%s')"):format(filePath), 2)
    end

    local result, err = loadModule(filePath, env)

    if result then return result() end

    error(err)
end

---@param filePath string
---@return table
---Loads and decodes a json file at the given path.
function lib.loadJson(filePath)
    if type(filePath) ~= 'string' then
        error(("file path must be a string (received '%s')"):format(filePath), 2)
    end

    local resourceSrc, modPath = getModuleInfo(filePath)
    local resourceFile = LoadResourceFile(resourceSrc, ('%s.json'):format(modPath))

    if resourceFile then
        return json.decode(resourceFile)
    end

    error(('cannot load json file at path %s'):format(modPath))
end

---Loads the given module, returns any value returned by the seacher (`true` when `nil`).\
---Passing `@resourceName.modName` loads a module from a remote resource.\
---@param modName string
---@return unknown
function lib.require(modName)
    if type(modName) ~= 'string' then
        error(("module name must be a string (received '%s')"):format(modName), 3)
    end

    local module = loaded[modName]

    if module == '__loading' then
        error(("^1circular-dependency occurred when loading module '%s'^0"):format(modName), 2)
    end

    if module ~= nil then return module end

    loaded[modName] = '__loading'

    local err = {}

    for i = 1, #package.searchers do
        local result, errMsg = package.searchers[i](modName)

        if result then
            if type(result) == 'function' then result = result() end
            loaded[modName] = result or result == nil

            return loaded[modName]
        end

        err[#err + 1] = errMsg
    end

    error(("%s"):format(table.concat(err, "\n\t")))
end

return lib.require
