require_relative "../test_helper"
require "banter/selectable_queue"

setup { Banter::SelectableQueue.new }

test "pushing onto the queue" do |queue|
  assert_equal queue.push(1), queue
end

test "popping off a non-empty queue" do |queue|
  queue.push 1
  queue.push 2

  assert_equal queue.pop, 1
  assert_equal queue.pop, 2
end

test "popping off an empty queue" do |queue|
  assert_raise(ThreadError) { queue.pop true }
end

test "getting the size of a non-empty queue" do |queue|
  queue.push 1
  queue.push 2

  assert_equal queue.size, 2
end

test "getting the size of an empty queue" do |queue|
  assert_equal queue.size, 0
end

test "selecting on a non-empty queue" do |queue|
  queue.push 1
  r, _ = IO.select [queue], nil, nil, 0

  assert_equal r, [queue]
end

test "selecting on an emptied queue" do |queue|
  queue.push(1).pop
  r, _ = IO.select [queue], nil, nil, 0

  assert_equal r, nil
end
