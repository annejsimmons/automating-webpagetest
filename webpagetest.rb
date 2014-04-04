#!/usr/bin/env ruby
 
require "net/http"
require "uri"
require "nokogiri"
require "csv"
require "mongoid"
require "chronic"
 
Mongoid.load!("mongoid.yml", :development)
 
class TestResults
    include Mongoid::Document
 
    field :timestamp_of_test, type: Time
    field :load_time, type: Integer
    field :time_to_first_byte, type: Integer
    field :csv_url, type: String
end
 
test_url = "http://www.bbc.co.uk/news/"
baseurl = "http://[WEB PAGE TEST SERVER]/runtest.php?runs=1&f=xml&fvonly=1&url=#{test_url}"
 
response = Net::HTTP.get(URI(baseurl))
doc  = Nokogiri::XML(response)
 
csv_url = doc.at_xpath('//summaryCSV').content
 
uri = URI.parse(csv_url)
http = Net::HTTP.new(uri.host, uri.port)
req = Net::HTTP::Post.new(uri.path)
 
while((csv_content = http.request(req)).class == Net::HTTPNotFound)
    sleep 5
end
 
raw_results = CSV.parse(csv_content.body, {:headers => true, :return_headers => true, :header_converters => :symbol, :converters => :all})
 
TestResults.create({
    :timestamp_of_test => Chronic.parse(raw_results[1][:time]),
    :load_time => raw_results[1][:load_time_ms],
    :time_to_first_byte => raw_results[1][:time_to_first_byte_ms],
    :csv_url => csv_url
    })