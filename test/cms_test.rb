ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"

require_relative "../cms"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def admin_session
    { "rack.session" => { user: "admin" } }
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def create_document(name, content="")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def session
    last_request.env["rack.session"]
  end

  def test_index
    create_document "about.md"
    create_document "changes.txt"

    get "/"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
  end

  def test_viewing_text_document
    create_document "history.txt", "1993 - Yukihiro Matsumoto dreams up Ruby."

    get "/history.txt"

    text = "1993 - Yukihiro Matsumoto dreams up Ruby."

    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, text
  end

  def test_document_not_found
    get "/notafile.txt" # Atempt to access a nonexistent file

    message = "notafile.txt does not exist"

    assert_equal 302, last_response.status  # Assert that the user was redirected
    assert_empty last_response.body
    assert_equal message, session[:message]

    get last_response["Location"] # Request the page that the user was redirected to
    assert_equal 200, last_response.status
    assert_includes last_response.body, message

    get "/" # Reload the page
    assert_equal 200, last_response.status
    refute_includes last_response.body, message # Assert that the message has been removed
  end

  def test_viewing_markdown_document
    create_document "about.md", "# Ruby is..."

    get "/about.md"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<h1>Ruby is...</h1>"
  end

  def test_editing_document
    create_document "changes.txt"

    get "/changes.txt/edit", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "</textarea>"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_editing_document_signed_out
    create_document "changes.txt"

    get "/changes.txt/edit"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_updating_document
    post "/changes.txt", { content: "new content" }, admin_session

    message = "changes.txt has been updated."
    
    assert_equal 302, last_response.status
    assert_equal message, session[:message]

    get last_response["Location"]

    assert_includes last_response.body, message

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end

  def test_updating_document_signed_out
    post "/changes.txt", { content: "new content" }

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_view_new_document_form
    get "/new", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_view_new_document_form_signed_out
    get "/new"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_deleting_documents
    create_document("test.txt")

    post "/test.txt/destroy", {}, admin_session

    message = "test.txt has been deleted."

    assert_equal 302, last_response.status
    assert_equal message, session[:message]

    get last_response["Location"]
    assert_includes last_response.body, message

    get "/"
    refute_includes last_response.body, "test.txt"
  end

  def test_deleting_documents_signed_out
    create_document("test.txt")

    post "/test.txt/destroy"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_creating_invalid_filename
    get "/new", {}, admin_session

    assert_equal 200, last_response.status
    
    message = "Please enter a valid filename ending with '.txt' or '.md'"

    post "/new", filename: "testfile"

    assert_equal 422, last_response.status
    assert_includes last_response.body, message
  end

  def test_creating_valid_file
    post "/new", { filename: "testfile.txt" }, admin_session

    assert_equal 302, last_response.status
    assert_equal "testfile.txt has been created.", session[:message]
    
    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "testfile.txt"
  end

  def test_creating_valid_file_signed_out
    post "/new", {filename: "testfile.txt"}

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_signin_form
    get "/users/signin"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_signin
    post "/users/signin", username: "admin", password: "secret"

    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]
    assert_equal "admin", session[:user]

    get last_response["Location"]
    assert_includes last_response.body, "Welcome!"
    assert_includes last_response.body, "Signed in as admin"
  end

  def test_signin_with_bad_credentials
    post "/users/signin", username: "guest", password: "shhhh"

    assert_equal 422, last_response.status
    assert_nil session[:user]
    assert_includes last_response.body, "Invalid credentials"
  end

  def test_signout
    post "/users/signout"

    message = "You have been signed out."

    assert_equal message, session[:message]

    get last_response["Location"]

    assert_includes last_response.body, "You have been signed out"
    assert_includes last_response.body, "Sign In"
    assert_nil session[:username]
  end

  def test_duplicate_file
    create_document "testfile.txt", "This is a test file..."

    post "/testfile.txt/duplicate", {}, admin_session

    assert_equal 302, last_response.status
    assert_equal "testfile.txt has been duplicated!", session[:message]
    
    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "testfile_copy.txt"
  end

  def test_signup_form
    get "/users/signup"

    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<button type="submit">Sign Up)
  end

  def test_signup_user_with_valid_credentials
    post "/users/signup", username: "developer", password: "letmein"

    assert_equal 302, last_response.status
    assert_equal "New user developer has been signed up, please sign in to access!", session[:message]

    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "please sign in to access!"
  end

  def test_signup_user_with_invalid_credentials
    post "/users/signup", username: "developer", password: "   "

    assert_equal 422, last_response.status
    assert_includes last_response.body, "Please enter a valid username and password"
  end
end