local encoder = {}
LookupTable = nn.LookupTable

function encoder.lstm(input_size, rnn_size, n, dropout, word_emb_size)
  dropout = dropout or 0 
  local vec_size = word_emb_size or rnn_size
  local inputs = {}
  table.insert(inputs, nn.Identity()()) -- x
  table.insert(inputs, nn.Identity()()) -- m
  for L = 1,n do
    table.insert(inputs, nn.Identity()()) -- prev_c[L]
    table.insert(inputs, nn.Identity()()) -- prev_h[L]
  end
  local x, input_size_L, word_vec
  local m = inputs[2]
  local outputs = {}
  for L = 1,n do
    -- c,h from previous timesteps
    local prev_h = inputs[L*2+2]
    local prev_c = inputs[L*2+1]
    -- the input to this layer
    if L == 1 then
      word_vec_layer = LookupTable(input_size, vec_size)
      word_vec_layer.name = 'enc_lookup'
      word_vec = word_vec_layer(inputs[1])            
      x = nn.Identity()(word_vec)
      input_size_L = vec_size
    else 
      x = outputs[(L-1)*2] 
      if dropout > 0 then x = nn.Dropout(dropout)(x) end -- apply dropout, if any
      input_size_L = rnn_size
    end
    -- evaluate the input sums at once for efficiency
    local i2h = nn.Linear(input_size_L, 4 * rnn_size)(x)
    local h2h = nn.Linear(rnn_size, 4 * rnn_size)(prev_h)
    local all_input_sums = nn.CAddTable()({i2h, h2h})
    -- decode the gates
    local sigmoid_chunk = nn.Narrow(2, 1, 3 * rnn_size)(all_input_sums)
    sigmoid_chunk = nn.Sigmoid()(sigmoid_chunk)
    local in_gate = nn.Narrow(2, 1, rnn_size)(sigmoid_chunk)
    local forget_gate = nn.Narrow(2, rnn_size + 1, rnn_size)(sigmoid_chunk)
    local out_gate = nn.Narrow(2, 2 * rnn_size + 1, rnn_size)(sigmoid_chunk)
    -- decode the write inputs
    local in_transform = nn.Narrow(2, 3 * rnn_size + 1, rnn_size)(all_input_sums)
    in_transform = nn.Tanh()(in_transform)
    -- perform the LSTM update
    local next_c           = nn.CAddTable()({
        nn.CMulTable()({forget_gate, prev_c}),
        nn.CMulTable()({in_gate,     in_transform})
      })
    -- gated cells form the output
    local next_h = nn.CMulTable()({out_gate, nn.Tanh()(next_c)})
    -- mask the states
    local next_c_masked = nn.Maskh()({prev_c, next_c, m})
    local next_h_masked = nn.Maskh()({prev_h, next_h, m})
    
    table.insert(outputs, next_c_masked)
    table.insert(outputs, next_h_masked)
  end
 
  return nn.gModule(inputs, outputs)
end

return encoder
