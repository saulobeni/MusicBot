defmodule MusicBotTest do
  use ExUnit.Case
  doctest MusicBot

  test "greets the world" do
    assert MusicBot.hello() == :world
  end
end
