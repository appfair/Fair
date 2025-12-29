// Copyright (c) 2022 - 2026 The App Fair Project <info@appfair.org>
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-or-later
import FairExpo
import class Foundation.RunLoop

Task {
    await FairToolCommand.main()
    FairToolCommand.exit()
}

RunLoop.main.run()
