--data
local commandHistory = {}
local itemTable = {}
local commands = {"sort", "request", "list", "index", "exit", "help"}


--utility functions
local function contains(...)
    local ret = {}
    for _,k in ipairs({...}) do ret[k] = true end
    return ret
 end

 local function hasSpace(chest)
    if table.getn(chest.list()) >= chest.size() then
        return false
    else
        return true
    end
end

--Finding Inventories and itemTable
if not (settings.get("INPUT_CHEST") and settings.get("OUTPUT_CHEST")) then
    printError("Input and Output chests not specified, defaulting to 'left' and 'right'. \nUse 'set INPUT_CHEST <chest name>' and 'set OUTPUT_CHEST <chest name>' to specify.")
end
local INPUT_CHEST = peripheral.wrap(settings.get("INPUT_CHEST") or "left")
local OUTPUT_CHEST = peripheral.wrap(settings.get("OUTPUT_CHEST") or "right")
local INVENTORIES_EXCLUDED = settings.get("INVENTORIES_EXCLUDED") or {}
local INVENTORIES = { peripheral.find("inventory",  
    function(name, wrap) --this function excludes the input and output chests from the table, and the names listed in INVENTORIES_EXCLUDED
        if name == peripheral.getName(INPUT_CHEST) or name == peripheral.getName(OUTPUT_CHEST) or name == "back" or name == "front" or name == "left" or name == "right" or name == "top" or name == "bottom"  or contains(table.unpack(INVENTORIES_EXCLUDED))[name] then
            return false    
        else
            return true
        end
    end
        ) }
local doIndex = true
do --read from itemTable.txt
    local file = fs.open("itemTable.txt", 'r')
    if file ~= nil then
        itemTable = textutils.unserialize(file.readAll())
        if itemTable ~= {} and itemTable ~= nil then
            doIndex = false
        end
        file.close()
    end
end
--RETURNS void
local function sort() --Polymorphic sorts the items in the input chest.
    -- local InputList = INPUT_CHEST.list()
    for name, chest in pairs(INVENTORIES) do -- check every chest in our inventories
        if INPUT_CHEST.list() == {} then break end
        print("checking " .. peripheral.getName(chest) .. " for free slots.")
        for fromSlot, item in pairs(INPUT_CHEST.list()) do --loop over every item in the input chest
            local cursor = { term.getCursorPos() }
            term.write("Checking input slot " .. fromSlot .. ". ")
            local iter = 0
            repeat
                local cursor2 = { term.getCursorPos() }
                term.write("ITERATION " .. iter)
                iter = iter + 1
                term.setCursorPos(cursor2[1], cursor2[2])
            until(INPUT_CHEST.pushItems(peripheral.getName(chest), fromSlot) == 0) -- can't push item in anymore
            term.setCursorPos(cursor[1], cursor[2])
        end
    end
    if INPUT_CHEST.list() ~= {} then return false, "not enough space" end
end

--RETURNS void
local function publish(itemTable) --writes itemTable to file.
    local file = fs.open("itemTable.txt", 'w')
    file.write(textutils.serialize(itemTable))
    file.close()
end

--RETURNS table of items, indexed by display name.
local function index() --indexes the items in the inventories by display name.
    local itemTable = {}
    table.setn(table.getn(INVENTORIES) * 27)
    for _, chest in pairs(INVENTORIES) do
        for slot, item in pairs(chest.list()) do
                local details = chest.getItemDetail(slot)
                local lowerName = string.lower(details.displayName)
                if itemTable[lowerName] == nil then itemTable[lowerName] = {} end -- null safety
                table.insert(itemTable[lowerName], {slot=slot, chestName=peripheral.getName(chest), count=details.count, name=item.name})
                local cursor = { term.getCursorPos() }
                term.clearLine()
                term.write(item.name .. " " .. item.count)
                term.setCursorPos(cursor[1], cursor[2])
        end
    end
    term.clearLine()
    publish(itemTable)
    return itemTable
end

-- RETURNS number of items transferred.
local function request(itemName, limit, itemTable) --finds and pulls an item from the inventories to the output chest.
    local slotTable = itemTable[string.lower(itemName)]
    if not slotTable then return 0 end
    local itemsTransferred = 0
    for i, details in ipairs(slotTable) do
        if limit == 0 then
            itemsTransferred = OUTPUT_CHEST.pullItems(details.chestName, details.slot)
        else
            itemsTransferred = OUTPUT_CHEST.pullItems(details.chestName, details.slot, limit)
        end
        if itemsTransferred >= limit then break end
    end
    return itemsTransferred
end
--RETURNS print-ready string of items and their amounts. 
local function list(query, itemTable) -- Lists all items whose names contain the search query.
    local listTable = {}
    for displayName, slotTable in pairs(itemTable) do
        if string.find(displayName, string.lower(query)) then
            local itemCount = 0
            for i, details in ipairs(slotTable) do
                itemCount = itemCount + details.count
            end
            listTable[displayName] = itemCount
        end
    end
    
    local printString = "Name\tCount\n"
    for name, count in pairs(listTable) do
        printString = printString .. name .. "\t" .. tostring(count) .. "\n"
    end
    return printString
end

--RETURNS void
local function cli(commandHistory, itemTable) --provides the command-line interface for action.
    while true do
        term.blit(">", "3", "f") -- blue prompt
        local command = read(nil, commandHistory)
        table.insert(commandHistory, command)
        local commandArgs = {}
        for substring in command:gmatch("%S+") do
        table.insert(commandArgs, substring)
        end
        command = string.lower(table.remove(commandArgs, 1) or "")
        if contains("sort", "s")[command] then
            print("Sorting...")
            local status, message = pcall(sort)
            if status then
                print("Done.")
            else
                printError(status)
                printError(textutils.serialize(message))
            end
            print("Indexing inventories...") --index again
            local code, iT = pcall(index)
            if code then
                itemTable = iT
            else
                printError(iT)
            end
        elseif contains("request", "r")[command] then
            limit = tonumber(table.remove(commandArgs, 1))
            local itemName = string.lower(table.concat(commandArgs, " "))
            if not limit then
                printError("Invalid Arguments. Usage: request <number> <display name>")
            else
                print("Requesting...")
                local code, res = pcall(request, itemName, limit, itemTable)
                if code then
                    print("Items requested: " .. tostring(res))
                else
                    printError(res)
                end
            end
        elseif contains("list", "l")[command] then
            local query = table.concat(commandArgs, " ")
            if not query then query = "" end --null safety
            print("Listing...")
            local code, resultString = pcall(list, query, itemTable)
            local _, y = term.getCursorPos()
            pcall(textutils.pagedPrint, resultString, y-2)
        elseif contains("exit", "0")[command] then
            print("exiting...")
            break
        elseif contains("index", "i")[command] then
            print("Indexing inventories...")
            local code, iT = pcall(index)
            if code then
                itemTable = iT
            else
                printError(iT)
            end
        elseif contains("publish", "pb")[command] then
            local status, message = pcall(publish)
            if status then
                print("Published to itemTable.txt.")
            else
                printError(status)
                printError(textutils.serialize(message))
            end
        elseif contains("help", "h")[command] then
            print("Available Commands: ")
            term.setTextColor(colors.magenta); print(table.concat(commands, ",")); term.setTextColor(colors.white)
            local hc = "help"
            if commandArgs[1] then
                hc = string.lower(commandArgs[1])
            end
            term.setTextColor(colors.green)
            if hc == "help" then
                print [[Help [command]: Prints available commands, or print help for a specific command. 
                Aliases: h [command] ]]
            elseif hc == "sort" then
                print [[Sort: Sorts the items in the input chest into the storage inventories, using polymorphic sorting (like items with like.)    
                Aliases: s]]
            elseif hc == "request" then
                print [[request <number> <display name>: requests <number> items of a specified name (exact display name, not case sensitive.) if <number> is 0, as many as possible are pulled.
                Aliases: r <number> <display name>]]
            elseif hc == "list" then
                print [[list [query]: List all of the items in the storage system, or the ones whose display names contain the specified query.
                Aliases: l [query] ]]
            elseif hc == "exit" then
                print [[exit: exits the prompt.
                Aliases: 0]]
            elseif hc == "index" then
                print [[index: indexes inventories. This command should be used after manually adding to or removing from the inventory system.
                Aliases: i]]
            elseif hc == "publish" then
                print [[publish: writes the inventory index to file. Deprecated command.
                Aliases: pb]]
            else
                print("Unknown Command.")
            end
            term.setTextColor(colors.white)
        elseif command == "" then
            term.clear()
            term.setCursorPos(1,1)
        else
            print("invalid command. Type help for help.")
        end
    end
end


--Indexing Inventories
term.setTextColor(colors.yellow)
if doIndex then
    print("Indexing Inventories...")
    itemTable = index()
end
print("PolySort v2") --Start for real
term.setTextColor(colors.white)
print("Available Commands: " .. table.concat(commands, ","))
cli({}, itemTable)
