import FairExpo
import class Foundation.RunLoop

Task {
    await FairToolCommand.main()
    FairToolCommand.exit()
}

RunLoop.main.run()
