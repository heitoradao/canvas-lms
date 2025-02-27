# frozen_string_literal: true

#
# Copyright (C) 2011 - present Instructure, Inc.
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

describe UserList do
  before do
    @account = Account.default
    @account.settings = { :open_registration => true }
    @account.save!
  end

  it "complains about invalid input" do
    ul = UserList.new "i\x01nstructure"
    expect(ul.errors).to eq [{ :address => "i\x01nstructure", :details => :unparseable }]
  end

  it "does not fail with unicode names" do
    ul = UserList.new '"senor molé" <blah@instructure.com>'
    expect(ul.errors).to eq []
    expect(ul.addresses.map { |x| [x[:name], x[:address]] }).to eq [["senor molé", "blah@instructure.com"]]
  end

  it "does not cause error with nothing past to it" do
    ul = UserList.new(nil)
    expect(ul.errors).to eq []
    expect(ul.addresses.map { |x| [x[:name], x[:address]] }).to eq []
  end

  it "finds by SMS number" do
    user_with_pseudonym(:name => "JT", :active_all => 1)
    communication_channel(@user, { username: '8015555555@txt.att.net', path_type: 'sms', active_cc: true })
    ul = UserList.new '(801) 555-5555'
    expect(ul.addresses).to eq [{ :address => '(801) 555-5555', :type => :sms, :user_id => @user.id, :name => 'JT', :shard => Shard.default }]
    expect(ul.errors).to eq []
    expect(ul.duplicate_addresses).to eq []

    ul = UserList.new '8015555555'
    expect(ul.addresses).to eq [{ :address => '(801) 555-5555', :type => :sms, :user_id => @user.id, :name => 'JT', :shard => Shard.default }]
    expect(ul.errors).to eq []
    expect(ul.duplicate_addresses).to eq []
  end

  it "processes a list of emails" do
    ul = UserList.new(regular)
    expect(ul.addresses.map { |x| [x[:name], x[:address]] }).to eql([
                                                                      ["Shaw, Ryan", "ryankshaw@gmail.com"],
                                                                      ["Last, First", "lastfirst@gmail.com"]
                                                                    ])
    expect(ul.errors).to eq []
    expect(ul.duplicate_addresses).to eq []
  end

  it "processes a list of irregular emails" do
    ul = UserList.new(%{ Shaw "Ryan" <ryankshaw@gmail.com>, \"whoopsies\" <stuff@stuff.stuff>,
          guess what my name has an@sign <blah@gmail.com>, <derp@derp.depr>})
    expect(ul.addresses.map { |x| [x[:name], x[:address]] }).to eql([
                                                                      ["Shaw \"Ryan\"", "ryankshaw@gmail.com"],
                                                                      ["whoopsies", "stuff@stuff.stuff"],
                                                                      ["guess what my name has an@sign", "blah@gmail.com"],
                                                                      [nil, "derp@derp.depr"]
                                                                    ])
    expect(ul.errors).to eq []
    expect(ul.duplicate_addresses).to eq []
  end

  it "processes a list of only emails, without brackets" do
    ul = UserList.new without_brackets
    expect(ul.addresses.map { |x| [x[:name], x[:address]] }).to eql([
                                                                      [nil, "ryankshaw@gmail.com"],
                                                                      [nil, "lastfirst@gmail.com"]
                                                                    ])
    expect(ul.errors).to eq []
    expect(ul.duplicate_addresses).to eq []
  end

  it "works with a mixed entry list" do
    ul = UserList.new regular + "," + %{otherryankshaw@gmail.com, otherlastfirst@gmail.com}
    expect(ul.addresses.map { |x| [x[:name], x[:address]] }).to eql([
                                                                      ["Shaw, Ryan", "ryankshaw@gmail.com"],
                                                                      ["Last, First", "lastfirst@gmail.com"],
                                                                      [nil, "otherryankshaw@gmail.com"],
                                                                      [nil, "otherlastfirst@gmail.com"]
                                                                    ])
    expect(ul.errors).to eq []
    expect(ul.duplicate_addresses).to eq []
  end

  it "works well with a single address" do
    ul = UserList.new('ryankshaw@gmail.com')
    expect(ul.addresses.map { |x| [x[:name], x[:address]] }).to eql([
                                                                      [nil, "ryankshaw@gmail.com"]
                                                                    ])
    expect(ul.errors).to eq []
    expect(ul.duplicate_addresses).to eq []
  end

  it "removes duplicates" do
    user = User.create!(:name => 'A 123451')
    user.pseudonyms.create!(:unique_id => "A123451", :account => @account)
    user = User.create!(:name => 'user 3')
    user.pseudonyms.create!(:unique_id => "user3", :account => @account)
    ul = UserList.new regular + "," + without_brackets + ", A123451, user3, A123451, user3", :root_account => @account
    expect(ul.addresses.map { |x| [x[:name], x[:address], x[:type]] }).to eql([
                                                                                ["Shaw, Ryan", "ryankshaw@gmail.com", :email],
                                                                                ["Last, First", "lastfirst@gmail.com", :email],
                                                                                ['A 123451', "A123451", :pseudonym],
                                                                                ['user 3', "user3", :pseudonym]
                                                                              ])
    expect(ul.errors).to eq []
    expect(ul.duplicate_addresses.map { |x| [x[:name], x[:address], x[:type]] }).to eql([
                                                                                          [nil, "ryankshaw@gmail.com", :email],
                                                                                          [nil, "lastfirst@gmail.com", :email],
                                                                                          ['A 123451', "A123451", :pseudonym],
                                                                                          ['user 3', "user3", :pseudonym]
                                                                                        ])

    ul = UserList.new regular + ",A123451 ,user3 ," + without_brackets + ", A123451, user3", :root_account => @account
    expect(ul.addresses.map { |x| [x[:name], x[:address], x[:type]] }).to eql([
                                                                                ["Shaw, Ryan", "ryankshaw@gmail.com", :email],
                                                                                ["Last, First", "lastfirst@gmail.com", :email],
                                                                                ['A 123451', "A123451", :pseudonym],
                                                                                ['user 3', "user3", :pseudonym]
                                                                              ])
    expect(ul.errors).to eq []
    expect(ul.duplicate_addresses.map { |x| [x[:name], x[:address], x[:type]] }).to eql([
                                                                                          [nil, "ryankshaw@gmail.com", :email],
                                                                                          [nil, "lastfirst@gmail.com", :email],
                                                                                          ['A 123451', "A123451", :pseudonym],
                                                                                          ['user 3', "user3", :pseudonym]
                                                                                        ])
  end

  it "is case insensitive when finding existing users" do
    @account.settings = { :open_registration => false }
    @account.save!

    user = User.create!(:name => 'user 3')
    user.pseudonyms.create!(:unique_id => "user3", :account => @account)
    user = User.create!(:name => 'user 4')
    user.pseudonyms.create!(:unique_id => "user4", :account => @account)
    communication_channel(user, { username: 'jt@instructure.com', active_cc: true })

    ul = UserList.new 'JT@INSTRUCTURE.COM, USER3', :root_account => @account
    expect(ul.addresses.map { |x| [x[:name], x[:address], x[:type]] }).to eql([
                                                                                ['user 4', 'jt@instructure.com', :email],
                                                                                ['user 3', 'user3', :pseudonym]
                                                                              ])
    expect(ul.errors).to eq []
  end

  it "is case insensitive when finding duplicates" do
    ul = UserList.new 'jt@instructure.com, JT@INSTRUCTURE.COM'
    expect(ul.addresses.length).to eq 1
    expect(ul.duplicate_addresses.length).to eq 1
  end

  it "processes login ids, SIS ids, and email addresses" do
    user = User.create!(:name => 'A 112351243')
    user.pseudonyms.create!(:unique_id => "A112351243", :account => @account)
    user = User.create!(:name => 'user 1')
    user.pseudonyms.create!(:unique_id => "user1", :account => @account)
    user = User.create!(:name => 'sneaky hobbitses')
    p = user.pseudonyms.create!(:unique_id => "whatever", :account => @account)
    p.sis_user_id = '9001'
    p.save!

    ul = UserList.new regular + "," + %{user1,test@example.com,A112351243,"thomas walsh" <test2@example.com>, 9001, "walsh, thomas" <test3@example.com>}, :root_account => @account
    expect(ul.addresses.map { |x| [x[:name], x[:address], x[:type]] }).to eql([
                                                                                ["Shaw, Ryan", "ryankshaw@gmail.com", :email],
                                                                                ["Last, First", "lastfirst@gmail.com", :email],
                                                                                ["user 1", "user1", :pseudonym],
                                                                                [nil, "test@example.com", :email],
                                                                                ["A 112351243", "A112351243", :pseudonym],
                                                                                ["thomas walsh", "test2@example.com", :email],
                                                                                ["sneaky hobbitses", "whatever", :pseudonym],
                                                                                ["walsh, thomas", "test3@example.com", :email]
                                                                              ])
    expect(ul.errors).to eq []
    expect(ul.duplicate_addresses).to eq []
  end

  it "does not process login ids if they don't exist" do
    user = User.create!(:name => 'A 112351243')
    user.pseudonyms.create!(:unique_id => "A112351243", :account => @account)
    user = User.create!(:name => 'user 1')
    user.pseudonyms.create!(:unique_id => "user1", :account => @account)
    ul = UserList.new regular + "," + %{user1,test@example.com,A112351243,"thomas walsh" <test2@example.com>, "walsh, thomas" <test3@example.com>,A4513454}, :root_account => @account
    expect(ul.addresses.map { |x| [x[:name], x[:address], x[:type]] }).to eql([
                                                                                ["Shaw, Ryan", "ryankshaw@gmail.com", :email],
                                                                                ["Last, First", "lastfirst@gmail.com", :email],
                                                                                ['user 1', "user1", :pseudonym],
                                                                                [nil, "test@example.com", :email],
                                                                                ['A 112351243', "A112351243", :pseudonym],
                                                                                ["thomas walsh", "test2@example.com", :email],
                                                                                ["walsh, thomas", "test3@example.com", :email]
                                                                              ])
    expect(ul.errors).to eq [{ :address => "A4513454", :type => :pseudonym, :details => :not_found }]
    expect(ul.duplicate_addresses).to eq []
  end

  it "pseudonyms should take precedence over emails" do
    @user1 = user_with_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => 1)
    @user2 = user_with_pseudonym(:name => 'Bob', :username => 'jt2@instructure.com', :active_all => 1)
    communication_channel(@user2, { username: 'jt@instructure.com', active_cc: true })
    ul = UserList.new 'jt@instructure.com'
    expect(ul.addresses).to eq [{ :type => :pseudonym, :address => 'jt@instructure.com', :user_id => @user1.id, :name => 'JT', :shard => Shard.default }]
    expect(ul.duplicate_addresses).to eq []
  end

  it "pseudonyms should take precedence over phone numbers" do
    @user1 = user_with_pseudonym(:name => 'JT', :username => '8015555555', :active_all => 1)
    @user2 = user_with_pseudonym(:name => 'Bob', :username => 'jt2@instructure.com', :active_all => 1)
    communication_channel(@user2, { username: '8015555555@tmomail.net', path_type: 'sms', active_cc: true })
    ul = UserList.new '8015555555'
    expect(ul.addresses).to eq [{ :type => :pseudonym, :address => '8015555555', :user_id => @user1.id, :name => 'JT', :shard => Shard.default }]
    expect(ul.duplicate_addresses).to eq []
  end

  it "works with a list of paths" do
    ul = UserList.new(['leonard@example.com', 'sheldon@example.com'],
                      :root_account => @account, :search_method => :preferred)
    expect(ul.addresses.count).to eq 2
    expect { ul.users }.to change(User, :count).by(2)
  end

  context "closed registration" do
    before do
      @account.settings = { :open_registration => false }
      @account.save!
    end

    it "does not return non-existing users if open registration is disabled" do
      ul = UserList.new 'jt@instructure.com'
      expect(ul.addresses).to eq []
      expect(ul.errors.length).to eq 1
      expect(ul.errors.first[:details]).to eq :not_found
    end

    it "picks the pseudonym, even if someone else has the CC" do
      user_with_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => 1)
      @user1 = @user
      user_with_pseudonym(:name => 'JT 1', :username => 'jt+1@instructure.com', :active_all => 1)
      communication_channel(@user, { username: 'jt@instructure.com', active_cc: true })
      ul = UserList.new 'jt@instructure.com'
      expect(ul.addresses).to eq [{ :address => 'jt@instructure.com', :type => :pseudonym, :user_id => @user1.id, :name => 'JT', :shard => Shard.default }]
      expect(ul.errors).to eq []
      expect(ul.duplicate_addresses).to eq []
    end

    it "complains if multiple people have the CC" do
      user_with_pseudonym(:username => 'jt@instructure.com', :active_all => true)
      communication_channel(@user, { username: 'jt+2@instructure.com', active_cc: true })
      user_with_pseudonym(:username => 'jt+1@instructure.com', :active_all => true)
      communication_channel(@user, { username: 'jt+2@instructure.com', active_cc: true })
      ul = UserList.new 'jt+2@instructure.com'
      expect(ul.addresses).to eq []
      expect(ul.errors).to eq [{ :address => 'jt+2@instructure.com', :type => :email, :details => :non_unique }]
      expect(ul.duplicate_addresses).to eq []
    end

    it "does not think that multiple pseudonyms for the same user is multiple users" do
      user_with_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => true)
      @user.pseudonyms.create!(:unique_id => 'jt+2@instructure.com')
      communication_channel(@user, { username: 'jt+3@instructure.com', active_cc: true })
      ul = UserList.new 'jt+3@instructure.com'
      expect(ul.addresses).to eq [{ :address => 'jt+3@instructure.com', :type => :email, :user_id => @user.id, :name => 'JT', :shard => Shard.default }]
      expect(ul.errors).to eq []
      expect(ul.duplicate_addresses).to eq []
    end

    it "detects duplicates, even from different CCs" do
      user_with_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => 1)
      communication_channel(@user, { username: '8015555555@txt.att.net', path_type: 'sms', active_cc: true })
      ul = UserList.new 'jt@instructure.com, (801) 555-5555'
      expect(ul.addresses).to eq [{ :address => 'jt@instructure.com', :type => :pseudonym, :user_id => @user.id, :name => 'JT', :shard => Shard.default }]
      expect(ul.errors).to eq []
      expect(ul.duplicate_addresses).to eq [{ :address => '(801) 555-5555', :type => :sms, :user_id => @user.id, :name => 'JT', :shard => Shard.default }]
    end

    it "chooses the active CC if there is 1 active and n unconfirmed" do
      user_with_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => true)
      communication_channel(@user, { username: 'jt+2@instructure.com', active_cc: true })
      @user1 = @user
      user_with_pseudonym(:name => 'JT 1', :username => 'jt+1@instructure.com', :active_all => true)
      communication_channel(@user, { username: 'jt+2@instructure.com' })
      ul = UserList.new 'jt+2@instructure.com'
      expect(ul.addresses).to eq [{ :address => 'jt+2@instructure.com', :type => :email, :user_id => @user1.id, :name => 'JT', :shard => Shard.default }]
      expect(ul.errors).to eq []
      expect(ul.duplicate_addresses).to eq []
    end

    # create the CCs in reverse order to check the logic when we see them in a different order
    it "chooses the active CC if there is 1 active and n unconfirmed, try 2" do
      user_with_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => true)
      communication_channel(@user, { username: 'jt+2@instructure.com' })
      @user1 = @user
      user_with_pseudonym(:name => 'JT 1', :username => 'jt+1@instructure.com', :active_all => true)
      communication_channel(@user, { username: 'jt+2@instructure.com', active_cc: true })
      ul = UserList.new 'jt+2@instructure.com'
      expect(ul.addresses).to eq [{ :address => 'jt+2@instructure.com', :type => :email, :user_id => @user.id, :name => 'JT 1', :shard => Shard.default }]
      expect(ul.errors).to eq []
      expect(ul.duplicate_addresses).to eq []
    end

    it "does not find users from untrusted accounts" do
      account = Account.create!
      user_with_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => true, :account => account)
      ul = UserList.new 'jt@instructure.com'
      expect(ul.addresses).to eq []
      expect(ul.errors).to eq [{ :address => 'jt@instructure.com', :type => :email, :details => :not_found }]
    end

    it "doesn't find site admins if you're not a site admin" do
      user_with_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => true, :account => Account.site_admin)
      allow(Account.default).to receive(:trusted_account_ids).and_return([Account.site_admin.id])
      jt = @user
      user_with_pseudonym
      other = @user

      ul = UserList.new 'jt@instructure.com', current_user: other
      expect(ul.addresses).to eq []
      expect(ul.errors).to eq [{ :address => 'jt@instructure.com', :type => :email, :details => :not_found }]

      # when it's the user _from_ site admin doing it, it can be found
      allow(Account.default).to receive(:trusted_account_ids).and_return([Account.site_admin.id])
      ul = UserList.new 'jt@instructure.com', current_user: jt
      expect(ul.addresses).to eq [{ :address => 'jt@instructure.com', :type => :pseudonym, :user_id => jt.id, :name => 'JT', :shard => Shard.default }]
      expect(ul.errors).to eq []
    end

    it "finds users from trusted accounts" do
      account = Account.create!
      allow(Account.default).to receive(:trusted_account_ids).and_return([account.id])
      user_with_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => true, :account => account)
      ul = UserList.new 'jt@instructure.com'
      expect(ul.addresses).to eq [{ :address => 'jt@instructure.com', :type => :pseudonym, :user_id => @user.id, :name => 'JT', :shard => Shard.default }]
      expect(ul.errors).to eq []
    end

    it "prefers a user from the current account instead of a trusted account" do
      user_with_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => true)
      @user1 = @user
      account = Account.create!
      allow(Account.default).to receive(:trusted_account_ids).and_return([account.id])
      user_with_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => true, :account => account)
      ul = UserList.new 'jt@instructure.com'
      expect(ul.addresses).to eq [{ :address => 'jt@instructure.com', :type => :pseudonym, :user_id => @user1.id, :name => 'JT', :shard => Shard.default }]
      expect(ul.errors).to eq []
    end

    it "prefers a user from the current account instead of a trusted account (reverse order)" do
      account = Account.create!
      allow(Account.default).to receive(:trusted_account_ids).and_return([account.id])
      user_with_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => true, :account => account)
      user_with_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => true)
      ul = UserList.new 'jt@instructure.com'
      expect(ul.addresses).to eq [{ :address => 'jt@instructure.com', :type => :pseudonym, :user_id => @user.id, :name => 'JT', :shard => Shard.default }]
      expect(ul.errors).to eq []
    end

    context 'when searching by sis id' do
      it "prefers a user from the current account instead of a trusted account" do
        account1 = Account.create!
        account2 = Account.create!
        allow(account1).to receive(:trusted_account_ids).and_return([account2.id])
        user_with_managed_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => true, :account => account1, :sis_user_id => "SISID")
        @user1 = @user
        user_with_managed_pseudonym(:name => 'JT', :username => 'jt2@instructure.com', :active_all => true, :account => account2, :sis_user_id => "SISID")
        ul = UserList.new 'SISID', :root_account => account1
        expect(ul.addresses).to eq [{ :address => 'jt@instructure.com', :type => :pseudonym, :user_id => @user1.id, :name => 'JT', :shard => Shard.default }]
        expect(ul.errors).to eq []
      end

      it "prefers a user from the current account instead of a trusted account (reverse order)" do
        account1 = Account.create!
        account2 = Account.create!
        allow(account2).to receive(:trusted_account_ids).and_return([account1.id])
        user_with_managed_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => true, :account => account1, :sis_user_id => "SISID")
        user_with_managed_pseudonym(:name => 'JT', :username => 'jt2@instructure.com', :active_all => true, :account => account2, :sis_user_id => "SISID")
        ul = UserList.new 'SISID', :root_account => account2
        expect(ul.addresses).to eq [{ :address => 'jt2@instructure.com', :type => :pseudonym, :user_id => @user.id, :name => 'JT', :shard => Shard.default }]
        expect(ul.errors).to eq []
      end
    end

    it "does not find a user if there is a conflict of unique_ids from not-this-account" do
      account1 = Account.create!
      account2 = Account.create!
      allow(Account.default).to receive(:trusted_account_ids).and_return([account1.id, account2.id])
      user_with_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => true, :account => account1)
      user_with_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => true, :account => account2)
      ul = UserList.new 'jt@instructure.com'
      expect(ul.addresses).to eq []
      expect(ul.errors).to eq [{ :address => 'jt@instructure.com', :type => :pseudonym, :details => :non_unique }]
    end

    it "finds a user with multiple not-this-account pseudonyms" do
      account1 = Account.create!
      account2 = Account.create!
      allow(Account.default).to receive(:trusted_account_ids).and_return([account1.id, account2.id])
      user_with_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => true, :account => account1)
      @user.pseudonyms.create!(:unique_id => 'jt@instructure.com', :account => account2)
      ul = UserList.new 'jt@instructure.com'
      expect(ul.addresses).to eq [{ :address => 'jt@instructure.com', :type => :pseudonym, :user_id => @user.id, :name => 'JT', :shard => Shard.default }]
      expect(ul.errors).to eq []
    end

    it "does not find a user from a different account by SMS" do
      account = Account.create!
      user_with_pseudonym(:name => "JT", :active_all => 1, :account => account)
      communication_channel(@user, { username: '8015555555@txt.att.net', path_type: 'sms', active_cc: true })
      ul = UserList.new '(801) 555-5555'
      expect(ul.addresses).to eq []
      expect(ul.errors).to eq [{ :address => '(801) 555-5555', :type => :sms, :details => :not_found }]
      expect(ul.duplicate_addresses).to eq []
    end
  end

  context "preferred selection" do
    it "finds an existing user if there is only one" do
      user_with_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => 1)
      communication_channel(@user, { username: 'jt+2@instructure.com', active_cc: true })
      ul = UserList.new 'jt+2@instructure.com', :search_method => :preferred
      expect(ul.addresses).to eq [{ :address => 'jt+2@instructure.com', :type => :email, :user_id => @user.id, :name => 'JT', :shard => Shard.default }]
      expect(ul.errors).to eq []
      expect(ul.duplicate_addresses).to eq []
      expect(ul.users).to eq [@user]
    end

    it "creates a new user if none exists" do
      ul = UserList.new 'jt@instructure.com', :search_method => :preferred
      expect(ul.addresses).to eq [{ :address => 'jt@instructure.com', :type => :email, :name => nil }]
      expect(ul.errors).to eq []
      expect(ul.duplicate_addresses).to eq []
    end

    it "creates a new user if multiple matching users are found" do
      @user1 = user_with_pseudonym(:name => 'JT', :username => 'jt+1@instructure.com')
      @user2 = user_with_pseudonym(:name => 'JT', :username => 'jt+2@instructure.com')
      communication_channel(@user1, { username: 'jt@instructure.com', active_cc: true })
      communication_channel(@user2, { username: 'jt@instructure.com', active_cc: true })
      ul = UserList.new 'jt@instructure.com', :search_method => :preferred
      expect(ul.addresses).to eq [{ :address => 'jt@instructure.com', :type => :email, :details => :non_unique }]
      expect(ul.errors).to eq []
      expect(ul.duplicate_addresses).to eq []
      users = ul.users
      expect(users.length).to eq 1
      expect(users.first).not_to eq @user1
      expect(users.first).not_to eq @user2
    end

    it "does not create a new user for non-matching non-email" do
      ul = UserList.new 'jt', :search_method => :preferred
      expect(ul.addresses).to eq []
      expect(ul.errors).to eq [{ :address => 'jt', :type => :pseudonym, :details => :not_found }]
      expect(ul.duplicate_addresses).to eq []
    end
  end

  context "user creation" do
    it "creates new users in creation_pending state" do
      ul = UserList.new 'jt@instructure.com'
      expect(ul.addresses.length).to eq 1
      expect(ul.addresses.first[:user_id]).to be_nil
      users = ul.users
      expect(users.length).to eq 1
      user = users.first
      expect(user).to be_creation_pending
      expect(user.root_account_ids).to eq [Account.default.id]
      expect(user.pseudonyms).to be_empty
      expect(user.communication_channels.length).to eq 1
      cc = user.communication_channels.first
      expect(cc.root_account_ids).to eq [Account.default.id]
      expect(cc.path_type).to eq 'email'
      expect(cc).to be_unconfirmed
      expect(cc.path).to eq 'jt@instructure.com'
    end

    it "creates new users even if a user already exists" do
      user_with_pseudonym(:name => 'JT', :username => 'jt+1@instructure.com', :active_all => 1)
      communication_channel(@user, { username: 'jt@instructure.com', active_cc: true })
      ul = UserList.new 'Bob <jt@instructure.com>'
      expect(ul.addresses).to eq [{ :address => 'jt@instructure.com', :type => :email, :name => 'Bob' }]
      users = ul.users
      expect(users.length).to eq 1
      user = users.first
      expect(user).not_to eq @user
      expect(user).to be_creation_pending
      expect(user.pseudonyms).to be_empty
      expect(user.communication_channels.length).to eq 1
      cc = user.communication_channels.first
      expect(cc.path_type).to eq 'email'
      expect(cc).to be_unconfirmed
      expect(cc.path).to eq 'jt@instructure.com'
      expect(cc).not_to eq @cc
    end

    it "does not create new users for users found by email" do
      user_with_pseudonym(:username => 'jt@instructure.com', :active_all => 1)
      @pseudonym.update_attribute(:unique_id, 'jt')
      ul = UserList.new 'jt@instructure.com', :root_account => Account.default, :search_method => :closed
      expect(ul.addresses.length).to eq 1
      expect(ul.addresses.first[:user_id]).to eq @user.id
      expect(ul.addresses.first[:type]).to eq :email
      expect(ul.users).to eq [@user]
    end

    it "defaults initial_enrollment_type for new users" do
      ul = UserList.new 'student1@instructure.com', :initial_type => 'StudentEnrollment'
      expect(ul.users.first.initial_enrollment_type).to eq 'student'
      ul = UserList.new 'student1@instructure.com', :initial_type => 'student'
      expect(ul.users.first.initial_enrollment_type).to eq 'student'
      ul = UserList.new 'observer1@instructure.com', :initial_type => 'StudentViewEnrollment'
      expect(ul.users.first.initial_enrollment_type).to eq 'student'
      ul = UserList.new 'teacher1@instructure.com', :initial_type => 'TeacherEnrollment'
      expect(ul.users.first.initial_enrollment_type).to eq 'teacher'
      ul = UserList.new 'teacher1@instructure.com', :initial_type => 'teacher'
      expect(ul.users.first.initial_enrollment_type).to eq 'teacher'
      ul = UserList.new 'ta1@instructure.com', :initial_type => 'TaEnrollment'
      expect(ul.users.first.initial_enrollment_type).to eq 'ta'
      ul = UserList.new 'ta1@instructure.com', :initial_type => 'ta'
      expect(ul.users.first.initial_enrollment_type).to eq 'ta'
      ul = UserList.new 'observer1@instructure.com', :initial_type => 'ObserverEnrollment'
      expect(ul.users.first.initial_enrollment_type).to eq 'observer'
      ul = UserList.new 'observer1@instructure.com', :initial_type => 'observer'
      expect(ul.users.first.initial_enrollment_type).to eq 'observer'
      ul = UserList.new 'designer1@instructure.com', :initial_type => 'DesignerEnrollment'

      expect(ul.users.first.initial_enrollment_type).to be_nil
      ul = UserList.new 'unknown1@instructure.com', :initial_type => 'UnknownThing'
      expect(ul.users.first.initial_enrollment_type).to be_nil
      # Left blank/default
      ul = UserList.new 'unknown1@instructure.com'
      expect(ul.users.first.initial_enrollment_type).to be_nil
    end
  end

  context "sharding" do
    specs_require_sharding

    it "finds a user from a trusted account in a different shard" do
      @shard1.activate do
        @account = Account.create!
        user_with_pseudonym(:name => 'JT', :username => 'jt@instructure.com', :active_all => true, :account => @account)
      end
      allow(Account.default).to receive(:trusted_account_ids).and_return([@account.id])
      ul = UserList.new 'jt@instructure.com'
      expect(ul.addresses).to eq [{ :address => 'jt@instructure.com', :type => :pseudonym, :user_id => @user.local_id, :name => 'JT', :shard => @shard1 }]
      expect(ul.errors).to eq []
      expect(ul.users).to eq [@user]
    end
  end
end

def regular
  %{"Shaw, Ryan" <ryankshaw@gmail.com>, "Last, First" <lastfirst@gmail.com>}
end

def without_brackets
  %{ryankshaw@gmail.com, lastfirst@gmail.com}
end
