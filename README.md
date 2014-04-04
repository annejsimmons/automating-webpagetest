WebPageTest is a great tool for seeing how well your website is performing. I was just on a project where the speed of a particular results page loading was the focus. How long the server took to respond, how long the UI took to render, what it was rendering, and where there were places for optimisations. We also wanted to measure the users' perceived page load time.
We wanted to create an automated test that would run regularly so that we could track changes in page load over time.

Reasons why we picked WebPageTest
<ul>
	<li>Ability to test any URL we wanted (ourselves, competitors, etc.)</li>
	<li>Multiple browsers that can be used to test pages</li>
	<li>Multiple locations and line speeds to test from</li>
	<li>Can be automated (they have a REST API)</li>
	<li>Ability to pin point a particular DOM element to measure load time of. For example we might consider the user perception of the page load as when there are 10 results on the page.</li>
	<li>Provides a waterfall of all the objects loaded onto the page so that we can look for optimisations.</li>
</ul>
We set up the following to prototype (read: not production quality)  a top line measurement tool that the business could use to see how performance was tracking from a users perspective. With only a week of these tests running we found 3 issues that had been causing major problems with the page load time.
<h2>Where to start?</h2>
WebPageTest provide a <a href="https://sites.google.com/a/webpagetest.org/docs/advanced-features/webpagetest-restful-apis">RESTful API</a> that we can use to interact with them. You will however have to host your own  private instance of WPT to be able to automate public URLs. You will also have to set up an agent for that instance to talk to.

Follow this guide for more information <a href="https://sites.google.com/a/webpagetest.org/docs/private-instances" target="_blank">Setting up a Private Instance of Web Page Test</a>. We set up  a couple of Amazon EC2 boxes for ours. (Make sure you pick at least Small rather than Micro)

Once you have that setup you should have a private instance of WebPageTest and URL that you can use to start manually testing your website.

For the purposes of this example I am going to test the BBC news website... I also used Ruby for this script. This was my first ever time creating a Ruby script for something like this, so keep that in mind!

These are some steps you can follow to build up a scripted test, and then store the results in a MongoDB for analysis later.
<h3>Step 1:</h3>
Call your instance of WebPageTest with your URL of choice and get back a 200 response

[code language="ruby"]
#!/usr/bin/env ruby
require "net/http"
require "uri"

test_url = "http://www.bbc.co.uk/news/"
baseurl = "http://[WEB PAGE TEST SERVER]/runtest.php?runs=1&f=xml&fvonly=1&url=#{test_url}"

response = Net::HTTP.get(URI(baseurl))
puts response
[/code]

At this point you should get a response that looks something like this:

[code language="xml"]
<!--?xml version="1.0" encoding="UTF-8"?-->

  200
  Ok
  <data>
    130723_9Y_BM
    d93f0a316369c61a891428dfb8b071d97b3dd19b
    http://[WEB PAGE TEST SERVER]/xmlResult/130723_9Y_BM/
    http://[WEB PAGE TEST SERVER]/result/130723_9Y_BM/
    http://[WEB PAGE TEST SERVER]/result/130723_9Y_BM/page_data.csv
    http://[WEB PAGE TEST SERVER]/result/130723_9Y_BM/requests.csv
    http://[WEB PAGE TEST SERVER]/jsonResult.php?test=130723_9Y_BM/
  </data>

[/code]

WebPageTest will asynchronously run the tests and dump the results into the locations returned above. As you can see there are lots of different formats that you can consume for the results data. Everything that I needed was in the summaryCSV.
<h3>Step 2:</h3>
Parse the URL to get the summaryCSV and then poll that until the results appear (as we have no idea of knowing when they will appear I checked every 5 seconds until I no longer got a 404 response). I then parse the CSV response into a 2 dimensional array, where the first array are the headers, and the second is their values. You can then see all the results that come back and which ones might be interesting for you.

[code language="ruby"]
#!/usr/bin/env ruby

require "net/http"
require "uri"
require "nokogiri"
require "csv"

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

puts raw_results
[/code]

<h3>Step 3:</h3>
Great! Now I have test results coming back and I want to save the ones I'm interested in so that I can visually represent them later and look at the changes in performance over time.
I'm going to use mongoDB to store the results of the tests. I created a class called TestResult with the fields that I am interested in from my WebPageTest results.
At this point you will need mongoDB up and running and you will also need a .yml file to define your mongoDB setup.
mongoid.yml

[code]
development:
  sessions:
    default:
      database: web_page_test_results
      hosts:
        - localhost:27017
[/code]

My scripts now looks like this:

[code language="ruby"]
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
[/code]

And my mongoDB happily contains the result of my first test, which will look something like this

[code]
db.test_results.find()
{ "_id" : ObjectId("51eef7cee055e6cee5000001"), "timestamp_of_test" : ISODate("2013-07-24T21:38:04Z"), "load_time" : 3566, "time_to_first_byte" : 317, "csv_url" : "http://[WEB PAGE TEST SERVER]/result/130723_RW_CN/page_data.csv" }
[/code]

<h3>What next?</h3>
If I had had a chance to extend this, I would of loved to of added visualisation, using a graphing framework and deploying the results to a web service so that everyone can see the change over time and drill down into any of the suspicious looking results.

Originally posted at <a href="http://annejsimmons.com/2013/07/26/automating-webpagetest-with-a-ruby-script/" /> 