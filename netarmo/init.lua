
FileToExecute="dht22-netarmo.lua"
l = file.list()
for k,v in pairs(l) do
  if k == FileToExecute then
    print("*** You've got 1 sec to stop timer ***")
    tmr.alarm(0, 1000, 0, function()
      if adc.force_init_mode(adc.INIT_VDD33)
      then
        node.restart()
        return -- don't bother continuing, the restart is scheduled
      end
      print("Executing ".. FileToExecute)
      dofile(FileToExecute)
    end)
  end
end
