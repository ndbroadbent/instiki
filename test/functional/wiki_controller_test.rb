#!/bin/env ruby

require File.dirname(__FILE__) + '/../test_helper'
require 'wiki_controller'
require 'rexml/document'

# Raise errors beyond the default web-based presentation
class WikiController; def rescue_action(e) logger.error(e); raise e end; end

class WikiControllerTest < Test::Unit::TestCase

  def setup
    setup_test_wiki
    setup_controller_test
  end

  def tear_down
    tear_down_wiki
  end


  def test_authenticate
    @web.password = 'pswd'
  
    r = process('authenticate', 'web' => 'wiki1', 'password' => 'pswd')
    assert_redirected_to :web => 'wiki1', :action => 'show', :id => 'HomePage'
    assert_equal ['pswd'], r.cookies['web_address']
  end

  def test_authenticate
    @web.password = 'pswd'
    
    r = process('authenticate', 'web' => 'wiki1', 'password' => 'wrong password')
    assert_redirected_to :action => 'login'
    assert_nil r.cookies['web_address']
  end


  def test_authors
    setup_wiki_with_three_pages
    @wiki.write_page('wiki1', 'BreakSortingOrder',
        "This page breaks the accidentally correct sorting order of authors",
        Time.now, Author.new('BreakingTheOrder', '127.0.0.2'))

    r = process('authors', 'web' => 'wiki1')

    assert_success
    assert_equal ['AnAuthor', 'BreakingTheOrder', 'Guest', 'TreeHugger'], 
        r.template_objects['authors']
  end


  def test_cancel_edit
    setup_wiki_with_three_pages
    @oak.lock(Time.now, 'Locky')
    assert @oak.locked?(Time.now)
  
    r = process('cancel_edit', 'web' => 'wiki1', 'id' => 'Oak')
    
    assert_redirected_to :action => 'show', :id => 'Oak'
    assert !@oak.locked?(Time.now)
  end


  def test_create_system
    ApplicationController.wiki = WikiServiceWithNoPersistence.new
    assert !@controller.wiki.setup?
    
    process('create_system', 'password' => 'a_password', 'web_name' => 'My Wiki', 
        'web_address' => 'my_wiki')
      
    assert_redirected_to :action => 'index'
    assert @controller.wiki.setup?
    assert_equal 'a_password', @controller.wiki.system[:password]
    assert_equal 1, @controller.wiki.webs.size
    new_web = @controller.wiki.webs['my_wiki']
    assert_equal 'My Wiki', new_web.name
    assert_equal 'my_wiki', new_web.address
  end

  def test_create_system_already_setup
    wiki_before = @controller.wiki
    assert @controller.wiki.setup?

    process 'create_system', 'password' => 'a_password', 'web_name' => 'My Wiki', 
        'web_address' => 'my_wiki'

    assert_redirected_to :action => 'index'
    assert_equal wiki_before, @controller.wiki
    # and no new wikis shuld be created either
    assert_equal 1, @controller.wiki.webs.size
  end


  def test_create_web
    @wiki.system[:password] = 'pswd'
  
    process 'create_web', 'system_password' => 'pswd', 'name' => 'Wiki Two', 'address' => 'wiki2'
    
    assert_redirected_to :web => 'wiki2', :action => 'show', :id => 'HomePage'
    wiki2 = @wiki.webs['wiki2']
    assert wiki2
    assert_equal 'Wiki Two', wiki2.name
    assert_equal 'wiki2', wiki2.address
  end

  def test_create_web_default_password
    @wiki.system[:password] = nil
  
    process 'create_web', 'system_password' => 'instiki', 'name' => 'Wiki Two', 'address' => 'wiki2'
    
    assert_redirected_to :web => 'wiki2', :action => 'show', :id => 'HomePage'
  end

  def test_create_web_failed_authentication
    @wiki.system[:password] = 'pswd'
  
    process 'create_web', 'system_password' => 'wrong', 'name' => 'Wiki Two', 'address' => 'wiki2'
    
    assert_redirected_to :web => nil, :action => 'index'
    assert_nil @wiki.webs['wiki2']
  end


  def test_edit
    r = process 'edit', 'web' => 'wiki1', 'id' => 'HomePage'
    assert_success
    assert_equal @wiki.read_page('wiki1', 'HomePage'), r.template_objects['page']
  end

  def test_edit_page_locked_page
    @home.lock(Time.now, 'Locky')
    process 'edit', 'web' => 'wiki1', 'id' => 'HomePage'
    assert_redirected_to :action => 'locked'
  end

  def test_edit_page_break_lock
    @home.lock(Time.now, 'Locky')
    process 'edit', 'web' => 'wiki1', 'id' => 'HomePage', 'break_lock' => 'y'
    assert_success
    assert @home.locked?(Time.now)
  end

  def test_edit_unknown_page
    process 'edit', 'web' => 'wiki1', 'id' => 'UnknownPage', 'break_lock' => 'y'
    assert_redirected_to :action => 'index'
  end


  def test_export_html
    setup_wiki_with_three_pages
    
    r = process 'export_html', 'web' => 'wiki1'
    
    assert_success
    assert_equal 'application/zip', r.headers['Content-Type']
    assert_match /attachment; filename="wiki1-html-\d\d\d\d-\d\d-\d\d-\d\d-\d\d-\d\d.zip"/, r.headers['Content-Disposition']
    # TODO assert contents of the output file
  end

  def test_export_markup
    r = process 'export_markup', 'web' => 'wiki1'

    assert_success
    assert_equal 'application/zip', r.headers['Content-Type']
    assert_match /attachment; filename="wiki1-textile-\d\d\d\d-\d\d-\d\d-\d\d-\d\d-\d\d.zip"/, r.headers['Content-Disposition']
    # TODO assert contents of the output file
  end
  

  def test_feeds
    process('feeds', 'web' => 'wiki1')
  end

  def test_index
    process('index')
    assert_redirected_to :web => 'wiki1', :action => 'show', :id => 'HomePage'
  end

  def test_index_multiple_webs
    @wiki.create_web('Test Wiki 2', 'wiki2')
    process('index')
    assert_redirected_to :action => 'web_list'
  end

  def test_index_multiple_webs_web_explicit
    process('index', 'web' => 'wiki2')
    assert_redirected_to :web => 'wiki2', :action => 'show', :id => 'HomePage'
  end

  def test_index_wiki_not_initialized
    ApplicationController.wiki = WikiServiceWithNoPersistence.new
    process('index')
    assert_redirected_to :action => 'new_system'
  end


  def test_list
    setup_wiki_with_three_pages

    r = process('list', 'web' => 'wiki1')

    assert_equal ['animals', 'trees'], r.template_objects['categories']
    assert_nil r.template_objects['category']
    assert_equal ['<a href="?category=animals">animals</a>', '<a href="?category=trees">trees</a>'],
        r.template_objects['category_links']
    assert_equal [@elephant, @home, @oak], r.template_objects['pages_in_category']
  end


  def test_locked
    @home.lock(Time.now, 'Locky')
    r = process('locked', 'web' => 'wiki1', 'id' => 'HomePage')
    assert_success
    assert_equal @home, r.template_objects['page']
  end


  def test_login
    r = process 'login', 'web' => 'wiki1'
    assert_success
    # this action goes straight to the templates
  end


  def test_new
    r = process('new', 'id' => 'NewPage', 'web' => 'wiki1')
    assert_success
    assert_equal 'AnonymousCoward', r.template_objects['author']
    assert_equal 'NewPage', r.template_objects['page_name']
  end


  def test_new_system
    ApplicationController.wiki = WikiServiceWithNoPersistence.new
    process('new_system')
    assert_success
  end

  def test_new_system_system_already_initialized
    assert @wiki.setup?
    process('new_system')
    assert_redirected_to :action => 'index'
  end


  def test_new_web
    @wiki.system['password'] = 'pswd'
    process 'new_web'
    assert_success
  end

  def test_new_web_no_password_set
    @wiki.system['password'] = nil
    process 'new_web'
    assert_redirected_to :action => 'index'
  end


  def test_print
    process('print', 'web' => 'wiki1', 'id' => 'HomePage')
    assert_success
  end


  def test_published
    @web.published = true
    
    r = process('published', 'web' => 'wiki1', 'id' => 'HomePage')
    
    assert_success
    assert_equal @home, r.template_objects['page']
  end


  def test_published_web_not_published
    @web.published = false
    
    r = process('published', 'web' => 'wiki1', 'id' => 'HomePage')

    assert_redirected_to :action => 'show', :id => 'HomePage'    
  end


  def test_recently_revised
    r = process('recently_revised', 'web' => 'wiki1')
    assert_success
    
    assert_equal [], r.template_objects['categories']
    assert_nil r.template_objects['category']
    assert_equal [@home], r.template_objects['pages_in_category']
    assert_equal 'the web', r.template_objects['set_name']
    assert_equal [], r.template_objects['category_links']
  end
  
  def test_recently_revised_with_categorized_page
    page2 = @wiki.write_page('wiki1', 'Page2',
        "Page2 contents.\n" +
        "category: categorized", 
        Time.now, Author.new('AnotherAuthor', '127.0.0.2'))
      
    r = process('recently_revised', 'web' => 'wiki1')
    assert_success
    
    assert_equal ['categorized'], r.template_objects['categories']
    # no category is specified in params
    assert_nil r.template_objects['category']
    assert_equal [@home, page2], r.template_objects['pages_in_category'],
        "Pages are not as expected: " +
        r.template_objects['pages_in_category'].map {|p| p.name}.inspect
    assert_equal 'the web', r.template_objects['set_name']
    assert_equal ['<a href="?category=categorized">categorized</a>'], 
        r.template_objects['category_links']
  end

  def test_recently_revised_with_categorized_page_multiple_categories
    setup_wiki_with_three_pages

    r = process('recently_revised', 'web' => 'wiki1')
    assert_success

    assert_equal ['animals', 'trees'], r.template_objects['categories']
    # no category is specified in params
    assert_nil r.template_objects['category']
    assert_equal [@elephant, @home, @oak], r.template_objects['pages_in_category'], 
        "Pages are not as expected: " +
        r.template_objects['pages_in_category'].map {|p| p.name}.inspect
    assert_equal 'the web', r.template_objects['set_name']
    assert_equal ['<a href="?category=animals">animals</a>', 
        '<a href="?category=trees">trees</a>'], 
        r.template_objects['category_links']
  end

  def test_recently_revised_with_specified_category
    setup_wiki_with_three_pages
      
    r = process('recently_revised', 'web' => 'wiki1', 'category' => 'animals')
    assert_success
    
    assert_equal ['animals', 'trees'], r.template_objects['categories']
    # no category is specified in params
    assert_equal 'animals', r.template_objects['category']
    assert_equal [@elephant], r.template_objects['pages_in_category']
    assert_equal "category 'animals'", r.template_objects['set_name']
    assert_equal ['<span class="selected">animals</span>', '<a href="?category=trees">trees</a>'], 
      r.template_objects['category_links']
  end


  def test_remove_orphaned_pages
    setup_wiki_with_three_pages
    @wiki.system[:password] = 'pswd'
    orhan_page_linking_to_oak = @wiki.write_page('wiki1', 'Pine',
        "Refers to [[Oak]].\n" +
        "category: trees", 
        Time.now, Author.new('TreeHugger', '127.0.0.2'))

    r = process('remove_orphaned_pages', 'web' => 'wiki1', 'system_password' => 'pswd')

    assert_redirected_to :action => 'list'
    assert_equal [@home, @oak], @web.select.sort,
        "Pages are not as expected: #{@web.select.sort.map {|p| p.name}.inspect}"


    # Oak is now orphan, second pass should remove it
    r = process('remove_orphaned_pages', 'web' => 'wiki1', 'system_password' => 'pswd')
    assert_redirected_to :action => 'list'
    assert_equal [@home], @web.select.sort,
        "Pages are not as expected: #{@web.select.sort.map {|p| p.name}.inspect}"

    # third pass does not destroy HomePage
    r = process('remove_orphaned_pages', 'web' => 'wiki1', 'system_password' => 'pswd')
    assert_redirected_to :action => 'list'
    assert_equal [@home], @web.select.sort,
        "Pages are not as expected: #{@web.select.sort.map {|p| p.name}.inspect}"
  end


  def test_revision
    r = process 'revision', 'web' => 'wiki1', 'id' => 'HomePage', 'rev' => '0'

    assert_success
    assert_equal @home, r.template_objects['page']
    assert_equal @home.revisions[0], r.template_objects['revision']
  end
  

  def test_rollback
    # rollback shows a form where a revision can be edited.
    # its assigns the same as or revision
    r = process 'revision', 'web' => 'wiki1', 'id' => 'HomePage', 'rev' => '0'

    assert_success
    assert_equal @home, r.template_objects['page']
    assert_equal @home.revisions[0], r.template_objects['revision']
  end


  def test_rss_with_content
    setup_wiki_with_three_pages
  
    r = process 'rss_with_content', 'web' => 'wiki1'
    
    assert_success
    pages = r.template_objects['pages_by_revision']
    assert_equal [@home, @oak, @elephant], pages,
        "Pages are not as expected: #{pages.map {|p| p.name}.inspect}"
    assert !r.template_objects['hide_description']
  end


  def test_rss_with_headlines
    setup_wiki_with_three_pages
    
    @request.host = 'localhost'
    @request.port = 8080
  
    r = process 'rss_with_headlines', 'web' => 'wiki1'
    
    assert_success
    pages = r.template_objects['pages_by_revision']
    assert_equal [@home, @oak, @elephant], pages,
        "Pages are not as expected: #{pages.map {|p| p.name}.inspect}"
    assert r.template_objects['hide_description']
    
    xml = REXML::Document.new(r.body)

    expected_page_links =
        ['http://localhost:8080/wiki1/show/HomePage',
         'http://localhost:8080/wiki1/show/Oak',
         'http://localhost:8080/wiki1/show/Elephant']

    assert_template_xpath_match '/rss/channel/link', 
        'http://localhost:8080/wiki1/show/HomePage'
    assert_template_xpath_match '/rss/channel/item/guid', expected_page_links
    assert_template_xpath_match '/rss/channel/item/link', expected_page_links
  end

  def test_save
    r = process 'save', 'web' => 'wiki1', 'id' => 'NewPage', 'content' => 'Contents of a new page', 
      'author' => 'AuthorOfNewPage'
    
    assert_redirected_to :web => 'wiki1', :action => 'show', :id => 'NewPage'
    assert_equal ['AuthorOfNewPage'], r.cookies['author'].value
    new_page = @wiki.read_page('wiki1', 'NewPage')
    assert_equal 'Contents of a new page', new_page.content
    assert_equal 'AuthorOfNewPage', new_page.author
  end

  def test_save_new_revision_of_existing_page
    @home.lock(Time.now, 'Batman')

    r = process 'save', 'web' => 'wiki1', 'id' => 'HomePage', 'content' => 'Revised HomePage', 
      'author' => 'Batman'

    assert_redirected_to :web => 'wiki1', :action => 'show', :id => 'HomePage'
    assert_equal ['Batman'], r.cookies['author'].value
    home_page = @wiki.read_page('wiki1', 'HomePage')
    assert_equal [home_page], @web.pages.values
    assert_equal 2, home_page.revisions.size
    assert_equal 'Revised HomePage', home_page.content
    assert_equal 'Batman', home_page.author
    assert !home_page.locked?(Time.now)
  end

  def test_save_new_revision_of_existing_page
    @home.lock(Time.now, 'Batman')

    r = process 'save', 'web' => 'wiki1', 'id' => 'HomePage', 'content' => 'Revised HomePage', 
      'author' => 'Batman'

    assert_redirected_to :web => 'wiki1', :action => 'show', :id => 'HomePage'
    assert_equal ['Batman'], r.cookies['author'].value
    home_page = @wiki.read_page('wiki1', 'HomePage')
    assert_equal [home_page], @web.pages.values
    assert_equal 2, home_page.revisions.size
    assert_equal 'Revised HomePage', home_page.content
    assert_equal 'Batman', home_page.author
    assert !home_page.locked?(Time.now)
  end


  def test_search
    setup_wiki_with_three_pages
    process 'search', 'web' => 'wiki1', 'query' => '\s[A-Z]ak'
    assert_redirected_to :action => 'show', :id => 'Oak'
  end

  def test_search_multiple_results
    setup_wiki_with_three_pages
    
    r = process 'search', 'web' => 'wiki1', 'query' => 'All about'
    
    assert_success
    assert_equal 'All about', r.template_objects['query']
    assert_equal [@elephant, @oak], r.template_objects['results']
  end

  def test_search_zero_results
    setup_wiki_with_three_pages
    
    r = process 'search', 'web' => 'wiki1', 'query' => 'non-existant text'
    
    assert_success
    assert_equal [], r.template_objects['results']
  end


  def test_show_page
    r = process('show', 'id' => 'HomePage', 'web' => 'wiki1')
    assert_success
    assert_match /First revision of the <a.*HomePage.*<\/a> end/, r.body
  end

  def test_show_page_with_multiple_revisions
    @wiki.write_page('wiki1', 'HomePage', 'Second revision of the HomePage end', Time.now, 
        Author.new('AnotherAuthor', '127.0.0.2'))

    r = process('show', 'id' => 'HomePage', 'web' => 'wiki1')

    assert_success
    assert_match /Second revision of the <a.*HomePage.*<\/a> end/, r.body
  end

  def test_show_page_nonexistant_page
    process('show', 'id' => 'UnknownPage', 'web' => 'wiki1')
    assert_redirected_to :web => 'wiki1', :action => 'new', :id => 'UnknownPage'
  end


  def test_update_web
    @wiki.system[:password] = 'pswd'
  
    process('update_web', 'system_password' => 'pswd',
        'web' => 'wiki1', 'address' => 'renamed_wiki1', 'name' => 'Renamed Wiki1',
        'markup' => 'markdown', 'color' => 'blue', 'additional_style' => 'whatever', 
        'safe_mode' => 'y', 'password' => 'new_password', 'published' => 'y', 
        'brackets_only' => 'y', 'count_pages' => 'y')

    assert_redirected_to :web => 'renamed_wiki1', :action => 'show', :id => 'HomePage'
    assert_equal 'renamed_wiki1', @web.address
    assert_equal 'Renamed Wiki1', @web.name
    assert_equal :markdown, @web.markup
    assert_equal 'blue', @web.color
    assert @web.safe_mode
    assert_equal 'new_password', @web.password
    assert @web.published
    assert @web.brackets_only
    assert @web.count_pages
  end


  def test_web_list
    another_wiki = @wiki.create_web('Another Wiki', 'another_wiki')
    
    r = process('web_list')
    
    assert_success
    assert_equal [another_wiki, @web], r.template_objects['webs']
  end
  
  
  # Wiki fixture

  def setup_test_wiki
    @wiki = ApplicationController.wiki = WikiServiceWithNoPersistence.new
    @web = @wiki.create_web('Test Wiki 1', 'wiki1')
    @home = @wiki.write_page('wiki1', 'HomePage', 'First revision of the HomePage end', Time.now, 
        Author.new('AnAuthor', '127.0.0.1'))
  end
  
  def setup_wiki_with_three_pages
    @oak = @wiki.write_page('wiki1', 'Oak',
        "All about oak.\n" +
        "category: trees", 
        5.minutes.ago, Author.new('TreeHugger', '127.0.0.2'))
    @elephant = @wiki.write_page('wiki1', 'Elephant',
        "All about elephants.\n" +
        "category: animals", 
        10.minutes.ago, Author.new('Guest', '127.0.0.2'))
  end
  
  def tear_down_wiki
    ApplicationController.wiki = nil
  end

end
