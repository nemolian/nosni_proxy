defmodule NosniProxyTest do
  use ExUnit.Case
  doctest NosniProxy

  test "greets the world" do
    assert NosniProxy.hello() == :world
  end
end
