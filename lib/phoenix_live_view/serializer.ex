defmodule Phoenix.LiveView.Serializer do
  @moduledoc false
  @behaviour Phoenix.Socket.Serializer
  @short 0
  @file_part 1

  alias Phoenix.Socket.Message
  defdelegate fastlane!(msg), to: Phoenix.Socket.V2.JSONSerializer
  defdelegate encode!(msg), to: Phoenix.Socket.V2.JSONSerializer


  def decode!(<<1::size(6), _parts_size :: size(10), _rest :: binary>> = raw_message, _opts) do
    decode_binary(raw_message)
  end

  def decode!(raw_message, opts) do
    Phoenix.Socket.V2.JSONSerializer.decode!(raw_message, opts)
  end

  @doc false
  def decode_binary(<<1::size(6), parts_size::size(10), rest::binary>>) do
    with {%Phoenix.Socket.Message{} = message, rest} <- decode_meta(rest) do
      decode_parts(parts_size, rest, message)
    end
  end

  def decode_binary(<<vsn::size(6), _parts_size::size(10), _rest::binary>>) when vsn != 1 do
    {:error, :invalid_version}
  end

  def decode_binary(_) do
    {:error, :invalid_binary}
  end

  def decode_parts(0, message, _acc) when byte_size(message) > 0 do
    {:error, :extra_parts}
  end

  def decode_parts(0, _, acc) do
    acc
  end

  @doc false
  def decode_parts(parts_size, <<type::size(8), _rest::binary>> = message, acc) do
    decoded =
      case type do
        @short -> decode_short(message, acc)
        @file_part -> decode_file(message, acc)
      end

    with {%Phoenix.Socket.Message{} = message, rest} <- decoded do
      decode_parts(parts_size - 1, rest, message)
    end
  end

  defp decode_meta(
         <<event_length::size(8), ref_length::size(8), join_ref_length::size(8),
           event::binary-size(event_length), ref::binary-size(ref_length),
           join_ref::binary-size(join_ref_length), rest::binary>>
       ) do
    {%Phoenix.Socket.Message{
       topic: "lv:#{join_ref}",
       event: event,
       ref: ref,
       join_ref: join_ref
     }, rest}
  end

  defp decode_meta(_) do
    {:error, :invalid_meta}
  end

  defp decode_short(
         <<@short::size(8), key_length::size(8), part_length::size(16),
           key::binary-size(key_length), part::binary-size(part_length), rest::binary>>,
         message
       ) do

    payload = Plug.Conn.Query.decode("#{key}=#{part}", message.payload || %{})
    {%{message | payload: payload}, rest}
  end

  defp decode_short(_, _) do
    {:error, :invalid_short}
  end

  defp decode_file(
    <<@file_part::size(8), key_length::size(8), meta_length :: size(16), part_length::size(32),
    key::binary-size(key_length), meta :: binary-size(meta_length), part::binary-size(part_length), rest::binary>>,
    message
  ) do

    %{"filename" => filename, "type" => content_type} = Plug.Conn.Query.decode(meta)

    # TODO: change this upload mechanism?
    path = Plug.Upload.random_file!("multipart")
    File.write(path, part)
    upload = %Plug.Upload{filename: filename, path: path, content_type: content_type}

    payload = Plug.Conn.Query.decode("#{key}", message.payload || %{})
    payload = put_in(payload, ["user", "upload"], upload)

    {%{message | payload: payload}, rest}
  end

  defp decode_file(_, _) do
    {:error, :invalid_file}
  end
end
