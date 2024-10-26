--[[
This file is the entry point for the Cubzh workspace. It loads a configuration from
a GitHub repository and uses it to configure the workspace. The configuration is
in JSON format and is loaded from the following URL:

https://github.com/kamikoluna/cubzh-lamdha-workspace-template/tree/main/.setup/config.json

The JSON file must contain the following keys:

* Map: the name of the map to load
* Items: a table of items to add to the map
* Modules: a table of modules to load

The Items table should contain the following keys for each item:

* id: the id of the item to add
* x: the x position of the item
* y: the y position of the item
* z: the z position of the item

The Modules table should contain the following keys for each module:

* id: the id of the module to load
* name: the name of the module
* version: the version of the module to load

The function `module_loader` is called when the client starts and loads the
configuration from the GitHub repository. It then sets the `Modules` table to the
modules specified in the configuration.

The `Client.OnStart` event is used to call the `module_loader` function when the
client starts.

The `Timer` function is used to garbage collect the Lua state every 5 seconds.
]]
--!stopSource
-- put your project here
local project_name = "kamikoluna/cubzh-lamdha-workspace-template"
local contributer = {}

function module_loader()
    -- Load the configuration from the GitHub repository
    local config = "https://github.com" .. project_name .. "tree/main/.setup/config.json"
    HTTP:Get(config, function(res)
        if res.StatusCode ~= 200 then
            print("Error " .. res.StatusCode)
            return
        end
        -- Decode the JSON response
        local js, err = JSON:Decode(res.Body)
        if err ~= nil then
            error(err)
        end
        local json = js[1]
        if type(json.Map) ~= "string" then
            error("Map must be a string type!")
        elseif type(json.Items) ~= "table" then
            error("Items must be a table type!")
        elseif type(json.Modules) ~= "table" then
            error("Modules must be a table type!")
        end
        __modules = json.Modules
        __items = json.Items
        __map = json.Map
    end)
    -- Garbage collect every 5 seconds
    Timer(5, false, function()
        collectgarbage("collect")
    end)
end

function code_loader()
    local config = "https://github.com" .. project_name .. "tree/main/World"
    self.client = function()
        HTTP:Get()
    end
    self.server = function()
    
    end
end

function workspace()
    self.bypass = function()
        if type(map) ~= "string" then 
            return
        elseif type(items) = "table" then
            return
        elseif type(Modules) ~= "table" then
            return
        end
            
    end
end
--[[
The `Client.OnStart` event is called when the client starts. It calls the
`module_loader` function to load the configuration from the GitHub repository.
]]

Client.OnStart = function()
    module_loader()
    workspace.bypass()
end

--[[
The `Modules` table is set to the modules specified in the configuration. It is
used to load the modules when the client starts.
]]

Modules = __modules
local map = __map
local items = __items
Config = { 
    Map = map,
    Items = {
        items
    }
}

