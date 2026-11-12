defmodule ExMontyCadServerWeb.PageController do
  use ExMontyCadServerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
