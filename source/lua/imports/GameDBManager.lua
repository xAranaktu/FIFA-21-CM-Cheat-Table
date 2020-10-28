local GameDBManager = {}

function GameDBManager:new(o, logger, memory_manager)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    self.logger = logger
    self.memory_manager = memory_manager

    self.tables = {}
    self.offsets = DB_TABLE_STRUCT_OFFSETS

    return o;
end

function GameDBManager:get_table_first_record(table_pointer)
    --self.logger:debug("get_table_first_record")
    return readPointer(table_pointer + self.offsets["first_record"])
end

function GameDBManager:get_table_record_size(table_pointer)
    -- self.logger:debug(string.format(
    --     "get_table_record_size: %X", table_pointer + self.offsets["record_size"]
    -- ))
    local result = readInteger(
        table_pointer + self.offsets["record_size"]
    )
    --self.logger:debug(result)
    return result
end

function GameDBManager:get_table_total_records(table_pointer)
    --self.logger:debug("get_table_total_records")
    return readSmallInteger(
        table_pointer + self.offsets["total_records"]
    )
end

function GameDBManager:get_table_written_records(table_pointer)
    -- self.logger:debug("get_table_written_records")
    return readSmallInteger(
        table_pointer + self.offsets["written_records"]
    )
end

function GameDBManager:clear_tables()
    self.tables = {}
end

function GameDBManager:add_table(table_name, pointer, first_record_write_to_arr)
    self.logger:debug(string.format(
        "add_table: %s", table_name
    ))

    if not pointer then
        local critical_error = string.format("Invalid pointer for %s. Restart FIFA and Cheat Engine", table_name)
        self.logger:critical(critical_error)
        assert(false, critical_error)
    end
    local table_data = {
        first_record =      self:get_table_first_record(pointer),
        record_size =       self:get_table_record_size(pointer),
        total_records =     self:get_table_total_records(pointer),
        written_records =   self:get_table_written_records(pointer),
    }
    self.tables[table_name] = table_data

    if first_record_write_to_arr then
        -- self.logger:debug(string.format("%s first record: %X", table_name, table_data["first_record"]))
        for i=1, #first_record_write_to_arr do
            writeQword(first_record_write_to_arr[i], table_data["first_record"])
        end
    end
end

function GameDBManager:find_record_addr(table_name, arr_flds, n_of_records_to_find)
    self.logger:debug(string.format("find_record_addr: %s", table_name))
    local first_record = self.tables[table_name]["first_record"]
    local record_size = self.tables[table_name]["record_size"]
    local written_records = self.tables[table_name]["written_records"]

    if n_of_records_to_find == nil then
        n_of_records_to_find = written_records + 1
    end

    self.logger:debug(string.format("first_record: %X", first_record))
    self.logger:debug(string.format("record_size: %d", record_size))
    self.logger:debug(string.format("written_records: %d", written_records))

    local row = 0
    local current_addr = first_record

    local result = {}
    local last_byte = 0
    local is_record_valid = true
    while true do
        if #result >= n_of_records_to_find then
            break
        end
        if row >= written_records then
            break
        end
        current_addr = first_record + (record_size*row)
        last_byte = readBytes(current_addr+record_size-1, 1, true)[1]
        is_record_valid = not (bAnd(last_byte, 128) > 0)
        if not is_record_valid then goto continue end

        for j=1, #arr_flds do
            local fld = arr_flds[j]
            local expr = fld["expr"]
            local values = fld["values"]

            local fld_val = self:get_table_record_field_value(
                current_addr, table_name, fld["name"]
            )

            for k=1, #values do
                local v = values[k]
                if expr == "eq" then
                    if fld_val == v then
                        table.insert(result, current_addr)
                    end
                end
            end
        end

        ::continue::
        row = row + 1
    end
    return result
end

function GameDBManager:get_table_record_field_value(record_addr, table_name, fieldname, raw)
    if raw == nil then raw = false end
    if not record_addr then
        self.logger:info(string.format("get_table_record_field_value: 0x%X: %s %s", record_addr or 0, table_name, fieldname))
        local critical_error = "ERROR. Restart FIFA and Cheat Engine. Open only one instance of Cheat Engine. Don't close cheat engine next time you play to avoid this problem."
        self.logger:critical(critical_error)
        assert(false, critical_error)
    end

    self.logger:info(string.format("get_table_record_field_value: 0x%X: %s %s", record_addr or 0, table_name or "", fieldname or ""))
    local meta_idx = DB_TABLES_META_MAP[table_name][fieldname]
    local fld_desc = DB_TABLES_META[table_name][meta_idx]

    local v = readInteger(record_addr + fld_desc["offset"])
    local a = bShr(v, fld_desc["startbit"])
    local b = bShl(1, fld_desc["depth"]) - 1
    local result = bAnd(a,b)

    if not raw then
        result = result + fld_desc["rangelow"]
    end

    return result
end

function GameDBManager:set_table_record_field_value(record_addr, table_name, fieldname, new_value, raw)
    if raw == nil then raw = false end
    local meta_idx = DB_TABLES_META_MAP[table_name][fieldname]
    local fld_desc = DB_TABLES_META[table_name][meta_idx]

    local addr = record_addr + fld_desc["offset"]
    local v = readInteger(addr)
    --self.logger:debug(string.format("writeval: %d", v))
    local startbit = fld_desc["startbit"]
    local depth = fld_desc["depth"]-1
    --self.logger:debug(string.format("Startbit: %d", startbit))
    --self.logger:debug(string.format("depth: %d", depth))

    --self.logger:debug(string.format("new_value: %d", new_value))
    if not raw then
        new_value = new_value - fld_desc["rangelow"]
    end
    for i=0, depth do
        --self.logger:debug(string.format("i: %d", i))
        local currentbit = startbit + i
        --self.logger:debug(string.format("currentbit: %d", currentbit))
        local is_set = bAnd(bShr(new_value, i), 1)
        --self.logger:debug(string.format("is_set: %d", is_set))

        if is_set == 1 then
            v = bOr(v, bShl(1, currentbit))
            --self.logger:debug(string.format("v is set: %d", v))
        else
            v = bAnd(v, bNot(bShl(1, currentbit)))
            --self.logger:debug(string.format("v not: %d", v))
        end
    end
    --self.logger:debug(string.format("writeval: %d", v))

    writeInteger(addr, v)
end


return GameDBManager;