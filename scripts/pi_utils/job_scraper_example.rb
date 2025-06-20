require 'kimurai'

class JobScraper < Kimurai::Base
    @name= 'eng_job_scraper'
    @start_urls = ["https://www.indeed.com/jobs?q=software+engineer&l=New+York%2C+NY"]
    @engine = :selenium_chrome

    @@jobs = []

    def scrape_page
        doc = browser.current_response
        returned_jobs = doc.css('td#resultsCol')
        returned_jobs.css('div.job_seen_beacon').each do |char_element|
            # scraping individual listings
            title = char_element.css('h2.jobTitle > a > span').text.gsub(/\n/, "")
            link = "https://indeed.com" + char_element.css('h2.jobTitle > a').attributes["href"].value.gsub(/\n/, "")
            description = char_element.css('div.job-snippet').text.gsub(/\n/, "")
            company = char_element.css('div.companyInfo > span.companyName').text.gsub(/\n/, "")
            location = char_element.css('div.companyInfo > div.companyLocation').text.gsub(/\n/, "")
            salary = char_element.css('span.estimated-salary > span').text.gsub(/\n/, "")

            # creating a job object
            job = {title: title, link: link, description: description, company: company, location: location, salary: salary}

            @@jobs << job if !@@jobs.include?(job)
        end
    end

    def parse(response, url:, data: {})

        10.times do
            scrape_page

            if browser.current_response.css('div#popover-background') || browser.current_response.css('div#popover-input-locationtst')
                browser.refresh
            end

            browser.find('/html/body/table[2]/tbody/tr/td/table/tbody/tr/td[1]/nav/div/ul/li[6]/a/span').click
            puts "🔹 🔹 🔹 CURRENT NUMBER OF JOBS: #{@@jobs.count}🔹 🔹 🔹"
            puts "🔺 🔺 🔺 🔺 🔺  CLICKED NEXT BUTTON 🔺 🔺 🔺 🔺 "
        end

        CSV.open('jobs.csv', "w") do |csv|
            csv << @@jobs
        end

        File.open("jobs.json","w") do |f|
            f.write(JSON.pretty_generate(@@jobs))
        end

        @@jobs
    end
end

jobs = JobScraper.crawl!
