# frozen_string_literal: true

#
# Copyright (C) 2015 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

describe ExternalFeedAggregator do
  context "#process_feed" do
    before(:once) do
      course_factory(active_all: true)
      @feed = external_feed_model
    end

    it "works correctly" do
      response = Net::HTTPSuccess.new(1.1, 200, "OK")
      expect(response).to receive(:body).and_return(rss_example)
      expect(CanvasHttp).to receive(:get).with(@feed.url).and_return(response)
      ExternalFeedAggregator.new.process_feed(@feed)

      expect(@feed.external_feed_entries.length).to eq 1
    end

    it "sets failure counts and refresh_at on failure" do
      expect(CanvasHttp).to receive(:get).with(@feed.url).and_raise(CanvasHttp::Error)
      ExternalFeedAggregator.new.process_feed(@feed)
      expect(@feed.failures).to eq 1
      expect(@feed.consecutive_failures).to eq 1
      expect(@feed.refresh_at).to be > 20.minutes.from_now
    end

    it "works correctly with atom" do
      response = Net::HTTPSuccess.new(1.1, 200, "OK")
      expect(response).to receive(:body).and_return(atom_example)
      expect(CanvasHttp).to receive(:get).with(@feed.url).and_return(response)
      ExternalFeedAggregator.new.process_feed(@feed)

      expect(@feed.external_feed_entries.length).to eq 1
    end

    it "sets the LiveEvents context" do
      response = Net::HTTPSuccess.new(1.1, 200, "OK")
      expect(response).to receive(:body).and_return(rss_example)
      expect(CanvasHttp).to receive(:get).with(@feed.url).and_return(response)
      expect(LiveEvents).to receive(:set_context).once
      ExternalFeedAggregator.new.process_feed(@feed)
    end
  end

  def rss_example
    %{<?xml version="1.0"?>
<rss version="2.0">
  <channel>
    <title>Lift Off News</title>
    <link>http://liftoff.msfc.nasa.gov/</link>
    <description>Liftoff to Space Exploration.</description>
    <language>en-us</language>
    <pubDate>Tue, 10 Jun 2003 04:00:00 GMT</pubDate>
    <lastBuildDate>Tue, 10 Jun 2003 09:41:01 GMT</lastBuildDate>
    <docs>http://blogs.law.harvard.edu/tech/rss</docs>
    <generator>Weblog Editor 2.0</generator>
    <managingEditor>editor@example.com</managingEditor>
    <webMaster>webmaster@example.com</webMaster>
    <ttl>5</ttl>

    <item>
      <title>Star City</title>
      <link>http://liftoff.msfc.nasa.gov/news/2003/news-starcity.asp</link>
      <description>How do Americans get ready to work with Russians aboard the
        International Space Station? They take a crash course in culture, language
        and protocol at Russia's Star City.</description>
      <pubDate>Tue, 03 Jun 2003 09:39:21 GMT</pubDate>
      <guid>http://liftoff.msfc.nasa.gov/2003/06/03.html#item573</guid>
    </item>
  </channel>
</rss>}
  end

  def atom_example
    %{<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">

 <title>Example Feed</title>
 <subtitle>A subtitle.</subtitle>
 <link href="http://example.org/feed/" rel="self"/>
 <link href="http://example.org/"/>
 <updated>2003-12-13T18:30:02Z</updated>
 <author>
   <name>John Doe</name>
   <email>johndoe@example.com</email>
 </author>
 <id>urn:uuid:60a76c80-d399-11d9-b91C-0003939e0af6</id>

 <entry>
   <title>Atom-Powered Robots Run Amok</title>
   <link href="http://example.org/2003/12/13/atom03"/>
   <id>urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a</id>
   <updated>2003-12-13T18:30:02Z</updated>
   <summary>Some text.</summary>
 </entry>

</feed>}
  end
end
