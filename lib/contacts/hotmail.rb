require 'csv'
require 'rubygems'
require 'nokogiri'

class Contacts
  class Hotmail < Base
    URL = "https://login.live.com/login.srf?id=2"
    CONTACT_LIST_URL = "https://mail.live.com/mail/GetContacts.aspx"
    PROTOCOL_ERROR = "Hotmail has changed its protocols, please upgrade this library first. If that does not work, report this error at http://rubyforge.org/forum/?group_id=2693"
    PWDPAD = "IfYouAreReadingThisYouHaveTooMuchFreeTime"

    def real_connect

      data, resp, cookies, forward = get(URL)
      old_url = URL
      until forward.nil?
        data, resp, cookies, forward, old_url = get(forward, cookies, old_url) + [forward]
      end

      postdata =  "PPSX=%s&PwdPad=%s&login=%s&passwd=%s&LoginOptions=2&PPFT=%s" % [
        CGI.escape(data.split("><").grep(/PPSX/).first[/=\S+$/][2..-3]),
        PWDPAD[0...(PWDPAD.length-@password.length)],
        CGI.escape(login),
        CGI.escape(password),
        CGI.escape(data.split("><").grep(/PPFT/).first[/=\S+$/][2..-3])
      ]

      form_url = data.split("><").grep(/form/).first.split[5][8..-2]
      data, resp, cookies, forward = post(form_url, postdata, cookies)

      old_url = form_url
      until cookies =~ /; PPAuth=/ || forward.nil?
        data, resp, cookies, forward, old_url = get(forward, cookies, old_url) + [forward]
      end

      if data.index("The e-mail address or password is incorrect")
        raise AuthenticationError, "Username and password do not match"
      elsif data != ""
        raise AuthenticationError, "Required field must not be blank"
      elsif cookies == ""
        raise ConnectionError, PROTOCOL_ERROR
      end

      data, resp, cookies, forward = get("http://mail.live.com/mail", cookies)
      until forward.nil?
        data, resp, cookies, forward, old_url = get(forward, cookies, old_url) + [forward]
      end


      @domain = URI.parse(old_url).host
      @cookies = cookies
    rescue AuthenticationError => m
      if @attempt == 1
        retry
      else
        raise m
      end
    end

    def contacts(options = {})
      if @contacts.nil? && connected?
        url = URI.parse(contact_list_url)
        data, resp, cookies, forward = get(get_contact_list_url, @cookies )
        
        @contacts = CSV.parse(data)[1..-1].map{|x| [x[1],x[3],x[79]]}.reject{|x| x[-1].blank?}.map do |row|
          # row is a triplet of first name, last namd and email address. Name is removed for unicode compliance. 
          # name = (row[0] || "") + " " + (row[1] || "")
          # name = row[2] if name == " "
          [row[2], row[2]]
        end
      else
        @contacts || []
      end
    end

    private

    TYPES[:hotmail] = Hotmail

    # the contacts url is dynamic
    # luckily it tells us where to find it
    def get_contact_list_url
      data = get(CONTACT_LIST_URL, @cookies)[0]
      html_doc = Nokogiri::HTML(data)
      html_doc.xpath("//a")[0]["href"]
    end
  end
end