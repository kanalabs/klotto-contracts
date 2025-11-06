# klotto-contracts

A Move-based lottery system on Aptos blockchain that manages lottery pots, ticket purchases, prize distribution, and treasury operations.

## Data Storage & Management

### Core Data Structures

#### LottoRegistry (Main Registry)
- **Pot Management**: Registry of all lottery pots with their addresses
- **Admin Control**: Super admin and admin addresses with role-based permissions
- **Treasury System**: Three separate fund stores (vault, cashback, take_rate)
- **Claim Thresholds**: Configurable limits for winning and cashback claims
- **Financial Stores**: USDC-based fungible asset stores for all operations

#### PotDetails (Individual Lottery Pots)
- **Pot Configuration**: Type (daily/biweekly/monthly/custom), pool type (fixed/dynamic)
- **Financial Data**: Ticket price, prize pool balance, individual prize store
- **Timing**: Creation timestamp, scheduled draw time
- **Status Management**: Active, paused, drawn, completed, cancelled states
- **Winners Registry**: Prize amounts, claim status, claimability flags
- **Refund System**: Tracking refunds for cancelled pots
- **Winning Numbers**: Generated lottery numbers (5 white balls + 1 powerball)

### Key Operations

#### Lottery Management
- **Pot Creation**: Admin-controlled lottery pot setup with configurable parameters
- **Ticket Purchasing**: User ticket purchases with number validation (1-69 white balls, 1-26 powerball)
- **Random Drawing**: Cryptographically secure random number generation for winners
- **Winner Announcement**: Batch processing of winners with prize allocation
- **Prize Claims**: User-initiated prize claiming with admin-controlled claimability

#### Financial Operations
- **Treasury Management**: Separate vaults for operational funds, cashbacks, and take rates
- **Fund Transfers**: Movement between pots, treasury, and user accounts
- **Refund Processing**: Automated refunds for cancelled lottery pots
- **Cashback System**: User cashback distribution with threshold controls

#### Administrative Controls
- **Role Management**: Super admin and admin role assignments
- **Pot Controls**: Pause/resume, cancellation, status management
- **Threshold Management**: Configurable claim limits for different operations
- **Fund Management**: Treasury operations and withdrawal controls

### Status States
- **Active**: Accepting ticket purchases
- **Paused**: Temporarily suspended
- **Drawn**: Numbers drawn, awaiting winner announcement
- **Completed**: Winners announced, prizes claimable
- **Cancelled**: Pot cancelled, refunds processing
- **Cancellation In Progress**: Processing refunds
- **Winner Announcement In Progress**: Processing winner announcements

### Security Features
- **Role-based Access**: Multi-level admin permissions
- **Input Validation**: Comprehensive validation for all operations
- **Balance Checks**: Insufficient balance protection
- **State Validation**: Proper state transitions and operation restrictions
- **Batch Processing**: Efficient handling of large winner/refund lists

### Asset Management
- **USDC Integration**: Primary fungible asset for all transactions
- **Store Management**: Individual stores for each pot and treasury component
- **Balance Tracking**: Real-time balance monitoring across all stores
- **Transfer Security**: Secure asset transfers with proper authorization

### Event System
Comprehensive event logging for:
- Pot lifecycle events (creation, drawing, completion)
- Financial transactions (purchases, claims, transfers)
- Administrative actions (role changes, threshold updates)
- Batch operations (winner announcements, refund processing)

This system provides a complete lottery infrastructure with robust financial management, security controls, and administrative oversight capabilities.