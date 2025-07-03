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
        #code to get only the listings
    end
  end

  def parse(response, url:, data: {})
    scrape_page
    @@jobs
  end
end

JobScraper.crawl!