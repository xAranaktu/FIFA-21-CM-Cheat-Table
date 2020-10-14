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
    return readPointer(table_pointer + self.offsets["first_record"])
end

function GameDBManager:get_table_record_size(table_pointer)
    return readInteger(
        readPointer(table_pointer + self.offsets["record_size"])
    )
end

function GameDBManager:get_table_total_records(table_pointer)
    return readSmallInteger(
        readPointer(table_pointer + self.offsets["total_records"])
    )
end

function GameDBManager:get_table_written_records(table_pointer)
    return readSmallInteger(
        readPointer(table_pointer + self.offsets["written_records"])
    )
end

function GameDBManager:clear_tables()
    self.tables = {}
end

function GameDBManager:add_table(table_name, pointer, first_record_write_to_arr)
    local table_data = {
        first_record =      self:get_table_first_record(pointer),
        record_size =       self:get_table_record_size(pointer),
        total_records =     self:get_table_total_records(pointer),
        written_records =   self:get_table_written_records(pointer),
    }
    self.tables[table_name] = data

    if first_record_write_to_arr then
        -- self.logger:debug(string.format("%s first record: %X", table_name, table_data["first_record"]))
        for i=1, #first_record_write_to_arr do
            writeQword(first_record_write_to_arr[i], table_data["first_record"])
        end
    end
end

function GameDBManager:get_table_record_field_value(record_addr, table_name, fieldname, raw)
    if raw == nil then raw = false end

    -- self.logger:debug(string.format("get_table_record_field_value: 0x%X: %s %s", record_addr, table_name, fieldname))
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


return GameDBManager;