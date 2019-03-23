defmodule Phoenix.LiveView.SerializerTest do
  alias Phoenix.LiveView.Serializer

  @short 0
  @file_part 1

  use ExUnit.Case

  describe "decode_binary!/1" do
    test "decodes when the version is correct" do
      join_ref = :crypto.strong_rand_bytes(16) |> Base.encode16()
      join_ref_length = String.length(join_ref)

      ref = :crypto.strong_rand_bytes(16) |> Base.encode16()
      ref_length = String.length(ref)

      event = "validate"
      event_length = String.length(event)

      meta_part =
        <<event_length::size(8), ref_length::size(8), join_ref_length::size(8), event::binary,
          ref::binary, join_ref::binary>>

      event_parts = <<@short::size(8), 11::size(8), 7::size(16), "_csrf_token", "my-csrf">> <>
        <<@short :: size(8), 10 :: size(8), 9 :: size(16), "user[name]" , "Test User" >> <>
        <<@short :: size(8), 11 :: size(8), 16 :: size(16), "user[email]" , "user@example.com" >> <>
        <<@file_part :: size(8), 12 :: size(8), 35 :: size(16), 16 :: size(32), "user[upload]" , "filename=upload.txt&type=text/plain", "my uploaded data" >>

      header = <<1::size(6), 4::size(10)>>
      message = header <> meta_part <> event_parts

      topic = "lv:#{join_ref}"
      assert %Phoenix.Socket.Message{
        topic: ^topic,
        event: "validate",
        ref: ^ref,
        join_ref: ^join_ref,
        payload: %{
          "_csrf_token" => "my-csrf",
          "user" => %{
            "name" => "Test User",
            "email" => "user@example.com",
            "upload" => %Plug.Upload{
              filename: "upload.txt",
              content_type: "text/plain",
              path: path
            }
          }
        },
      } = Serializer.decode_binary(message)

      assert File.read!(path) == "my uploaded data"
    end

    test "errors when the version is incorrect" do
      message = <<2::size(6), 1::size(10), 0>>
      assert Serializer.decode_binary(message) == {:error, :invalid_version}
    end
  end

  # %Phoenix.Socket.Message{
  #  event: "event",
  #  join_ref: "1",
  #  payload: %{
  #    "event" => "validate",
  #    "type" => "form",
  #    "value" => "_csrf_token=LA0eMi8MUgIrBxkNfT96WQd%2FHTp9EAAAbDvBkucmY3C58SHnUMXP2g%3D%3D&_utf8=%E2%9C%93&user%5Busername%5D=f&user%5Bemail%5D=&user%5Bphone_number%5D=&user%5Bavatar%5D=%5Bobject+File%5D"
  #  },
  #  ref: "2",
  #  topic: "lv:phx-MkyZuFmmaQU="
  # }

  # %Phoenix.Socket.Message{
  #  event: "validate",
  #  join_ref: "1",
  #  payload: %{
  #   _csrf_token=LADASD,
  #   user[name]=booo
  #    "type" => "form",
  #    "value" => "_csrf_token=LA0eMi8MUgIrBxkNfT96WQd%2FHTp9EAAAbDvBkucmY3C58SHnUMXP2g%3D%3D&_utf8=%E2%9C%93&user%5Busername%5D=f&user%5Bemail%5D=&user%5Bphone_number%5D=&user%5Bavatar%5D=%5Bobject+File%5D"
  #  },
  #  ref: "2",
  #  topic: "lv:phx-MkyZuFmmaQU="
  # }
end
