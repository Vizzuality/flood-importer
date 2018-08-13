require 'pg'
require 'csv'
require 'ruby-progressbar'


conn = PGconn.connect(host: "localhost", port: 5432, user: 'postgres', dbname: 'flood')

large_files = %w[Raw_agg_Coastal_City_POPexp]
MAX_COLUMNS = 1000

Dir['floods_vizzuality/Flood_Data/*.csv'].each do |f|
  # Gets table name from filename
  tablename = f[/[^\/]+(?=\.csv)/, 0]
  puts "Starting with file #{tablename}"

  first_row = nil
  # Gets the type of data of each row
  File.open(f) do |file|
    file.gets
    first_row = CSV.parse(file.first).first
  end

  # Gets the columns names
  file = File.open(f)
  columns = CSV.parse(file.first).first
  columns.map! { |x| x.nil? ? 'id' : x }

  # Information for the progress bar
  number_of_lines = file.readlines.size / 100

  # List of string columns
  string_columns = []

  # Construct create table query:
  query = "CREATE TABLE IF NOT EXISTS #{tablename} ("
  query << columns.each_with_index.map do |c, i|
    begin
      Float(first_row[i])
      large_files.include?(tablename) ? "#{c} real" : "#{c} float"
    rescue
      string_columns << c
      "#{c} varchar"
    end

  end.join(', ')
  query << ');'

  conn.exec(query)
  progress_bar = ProgressBar.create(title: tablename)

  line = 0
  CSV.foreach(f, col_sep: ',', row_sep: :auto, headers: true, encoding: 'UTF-8') do |row|
    line += 1
    if line > number_of_lines
      progress_bar.increment
      line = 0
    end
    data = row.to_a
    # Most files have the id field without name, so this hack fixes it
    data[0][0] = 'id' if data[0][0].nil?

    column_number = 0
    row_id = nil
    loop do
      columns = []
      values = []

      data[column_number...(column_number + MAX_COLUMNS)].each do |d|
        next if d.first.nil? || d.last.nil?
        columns << d.first
        values << (string_columns.include?(d.first) ? "'#{d.last.gsub("'", "''")}'" : d.last)
      end

      if column_number.zero?
        insert_query = "INSERT INTO #{tablename} ("
        insert_query << columns.join(', ')
        insert_query << ') VALUES ( ' + values.join(', ') + ') RETURNING id;'
      else
        col_val = columns.each_with_index.map { |e, i| " #{e} = #{values[i]}" }
        insert_query = "UPDATE #{tablename} SET"
        insert_query << col_val.join(', ')
        insert_query << " WHERE id = '#{row_id}' RETURNING id;"
      end

      begin
        response = conn.exec(insert_query)
        row_id = response[0]['id'] if response[0] && response[0]['id']
      rescue
        puts insert_query
      end
      column_number += MAX_COLUMNS
      break if column_number > data.length
    end
  end
  progress_bar.finish
  puts "Finished inserting the data for table #{tablename}"

end