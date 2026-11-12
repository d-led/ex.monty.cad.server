defmodule ExMontyCadServerWeb.Router do
  use ExMontyCadServerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ExMontyCadServerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ExMontyCadServerWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # The protocol is the API: one JSON-RPC message a request, answered with the
  # reply. It is `:api` rather than `:browser` because a client is a program —
  # there is no session cookie to carry and no form to protect.
  scope "/", ExMontyCadServerWeb do
    pipe_through :api

    post "/mcp", McpController, :handle
  end

  # Other scopes may use custom stacks.
  # scope "/api", ExMontyCadServerWeb do
  #   pipe_through :api
  # end
end
