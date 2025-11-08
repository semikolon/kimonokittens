# Contract Requirements & Validation

## Critical Requirements

### Payment Information
- **Swish**: **TODO: Extract from `www/kimonokittens-swish-qr.png`** (house account, NOT personal number)
- **Due Date**: 27th of each month
- **Currency**: SEK (Swedish kronor)

### Landlord Information (Förstahandshyresgäst)
- **Name**: Fredrik Bränström
- **Personnummer**: 8604230717
- **Phone**: 073-830 72 22
- **Email**: branstrom@gmail.com

### Property Information
- **Address**: Sördalavägen 26, 141 60 Huddinge
- **Type**: Rum och gemensamma ytor i kollektiv

### Contract Terms
- **Notice Period**: 2 months written notice
- **Contract Type**: Indefinite duration (tills vidare)
- **Signature Method**: Digital with BankID via Zigned

## Styling Requirements

### Visual Consistency
- **Must match dashboard aesthetic exactly**
- Background: `radial-gradient(circle at center, rgb(28,22,35) 0%, rgb(25,18,32) 100%)`
- Widget boxes: `rgba(49, 46, 129, 0.15)` with 16px rounded corners
- Text color: `rgb(221, 214, 254)` (text-purple-200)

### Typography
- **Main title**: Horsemen font, single line "HYRESAVTAL"
- **Section headings**: Galvji font, **UPPERCASE**, 0.8em, matching dashboard heatpump schedule bar
- **Body text**: Galvji font (Swedish character support: å, ä, ö)
- **Logo**: 360px width, top right position

### Layout
- **Zero margins**: Edge-to-edge background
- **No white pixel lines**: Gradient overlay extended to -1px with calc(100% + 2px)
- **Gradient overlays**: Static versions of dashboard animated gradients

## Tenant-Specific Data

Each contract must include:
- Tenant full name
- Personnummer (10 digits + optional hyphen)
- Phone number
- Email address
- Move-in date (YYYY-MM-DD format)
- Monthly rent amount

## Validation Rules

### Required Fields
- ✅ All landlord info must be present
- ✅ All tenant info must be present
- ✅ Property address must be correct
- ✅ Payment details (BankGiro + Swish) must be correct
- ✅ Move-in date must be valid ISO date

### Formatting Rules
- ✅ Personnummer: 10 or 12 digits (with/without century)
- ✅ Phone numbers: Swedish format (07X XXX XX XX or +467X XXX XX XX)
- ✅ Email: Valid email format
- ✅ Rent amount: Number with optional decimals, space-separated thousands

### Visual Rules
- ✅ Logo must render (file exists and loads)
- ✅ Fonts must load (Horsemen for h1, Galvji for rest)
- ✅ No "Information saknas" text in any section
- ✅ Section headings must be UPPERCASE
- ✅ Background must extend edge-to-edge (no white margins)

## Security Requirements

### Data Protection
- ✅ Tenant data stored in separate JSON files
- ✅ No sensitive data in git commits (personal info is OK for this internal tool)
- ✅ Webhook signatures verified for e-signature callbacks

### Digital Signatures
- ✅ Must use BankID for legal validity
- ✅ Signature verification via Zigned webhook
- ✅ Both parties must sign before contract is valid

## File Organization

```
contracts/
├── tenants/              # Tenant data JSON files
│   ├── sanna.json
│   └── frida.json
├── generated/            # Generated PDF contracts
│   └── [Name]_Hyresavtal_[Date].pdf
└── [Name]_Hyresavtal_[Date].md  # Markdown source contracts
```

## Test Coverage

### Unit Tests (spec/contract_generator_spec.rb)
- [ ] Tenant info extraction from markdown
- [ ] Section extraction (all 10 sections)
- [ ] Rent calculation formatting
- [ ] Date formatting (contract period)
- [ ] Template data preparation

### Integration Tests (spec/contract_generation_integration_spec.rb)
- [ ] End-to-end PDF generation
- [ ] Logo rendering verification
- [ ] Font loading verification
- [ ] Section content validation
- [ ] Visual regression (compare against reference PDF)

### Validation Tests (spec/contract_validation_spec.rb)
- [ ] Payment info correctness (Swish number from house account QR code)
- [ ] Landlord info presence
- [ ] Tenant info presence
- [ ] Required sections present
- [ ] No "Information saknas" text
- [ ] UPPERCASE section headings

## Future Enhancements

- [ ] Automated visual regression testing (PDF screenshots)
- [ ] Contract versioning and templates
- [ ] Multi-language support
- [ ] Bulk contract generation
- [ ] Contract renewal workflow

