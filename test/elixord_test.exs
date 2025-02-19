defmodule ElixordTest do
  use ExUnit.Case
  doctest Elixord

  test "greets the world" do
    assert Elixord.hello() == :world
  end
end
