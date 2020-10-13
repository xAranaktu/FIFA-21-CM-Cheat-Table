local GameDBManager = {}

function GameDBManager:new(o, logger, memory_manager)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    self.logger = logger
    self.memory_manager = memory_manager

    self.tables = {}
    self.tables_meta = DB_TABLES_META
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
        self.logger:debug(string.format("%s first record: %X", table_name, table_data["first_record"]))
        for i=1, #first_record_write_to_arr do
            writeQword(first_record_write_to_arr[i], table_data["first_record"])
        end
    end
end

function GameDBManager:get_table_record_field()

end


return GameDBManager;