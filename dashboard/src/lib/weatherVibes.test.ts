import { describe, it, expect } from 'vitest'
import { detectVibeKey, VIBES, getVibe, type WeatherParams } from './weatherVibes'

// Helper to create params with defaults
const params = (overrides: Partial<WeatherParams>): WeatherParams => ({
  temp: 10,
  wind: 10,
  condition: '',
  ...overrides,
})

describe('weatherVibes', () => {
  describe('VIBES constant', () => {
    it('has both short and long versions for every vibe', () => {
      for (const [key, vibe] of Object.entries(VIBES)) {
        expect(vibe.short, `${key} missing short`).toBeTruthy()
        expect(vibe.long, `${key} missing long`).toBeTruthy()
      }
    })

    it('short versions are max 15 chars (fit in forecast row)', () => {
      for (const [key, vibe] of Object.entries(VIBES)) {
        expect(vibe.short.length, `${key}.short too long: "${vibe.short}"`).toBeLessThanOrEqual(15)
      }
    })
  })

  describe('detectVibeKey', () => {
    describe('extreme conditions', () => {
      it('returns stormy for wind >= 40 kph', () => {
        expect(detectVibeKey(params({ wind: 40 }))).toBe('stormy')
        expect(detectVibeKey(params({ wind: 50 }))).toBe('stormy')
      })

      it('returns sleet for snöblandat conditions', () => {
        expect(detectVibeKey(params({ condition: 'Snöblandat regn' }))).toBe('sleet')
        expect(detectVibeKey(params({ condition: 'snöblandat' }))).toBe('sleet')
      })
    })

    describe('snow conditions', () => {
      it('returns snow_windy for snow + wind >= 25', () => {
        expect(detectVibeKey(params({ condition: 'Snöfall', wind: 25 }))).toBe('snow_windy')
        expect(detectVibeKey(params({ condition: 'Lätt snöfall', wind: 30 }))).toBe('snow_windy')
      })

      it('returns snow for snow without wind', () => {
        expect(detectVibeKey(params({ condition: 'Snöfall' }))).toBe('snow')
        expect(detectVibeKey(params({ condition: 'Lätt snöfall' }))).toBe('snow')
        expect(detectVibeKey(params({ condition: 'Kraftigt snöfall' }))).toBe('snow')
      })

      it('prefers sleet over snow for snöblandat', () => {
        expect(detectVibeKey(params({ condition: 'Snöblandat regn' }))).toBe('sleet')
      })
    })

    describe('rain conditions', () => {
      it('returns rain_windy for rain + wind >= 25', () => {
        expect(detectVibeKey(params({ condition: 'Regn', wind: 25 }))).toBe('rain_windy')
        expect(detectVibeKey(params({ condition: 'Kraftigt regn', wind: 30 }))).toBe('rain_windy')
      })

      it('returns rain for moderate rain conditions', () => {
        expect(detectVibeKey(params({ condition: 'Måttligt regn' }))).toBe('rain')
        expect(detectVibeKey(params({ condition: 'Regnskurar' }))).toBe('rain')
        expect(detectVibeKey(params({ condition: 'Områden med regn' }))).toBe('rain')
      })

      // TDD: Rain intensity tests
      describe('rain intensity', () => {
        it('returns rain_light for light rain conditions', () => {
          expect(detectVibeKey(params({ condition: 'Lätt regn' }))).toBe('rain_light')
          expect(detectVibeKey(params({ condition: 'Lätt duggregn' }))).toBe('rain_light')
          expect(detectVibeKey(params({ condition: 'Duggregn' }))).toBe('rain_light')
          expect(detectVibeKey(params({ condition: 'Lätt regnskur' }))).toBe('rain_light')
        })

        it('returns rain_heavy for heavy rain conditions', () => {
          expect(detectVibeKey(params({ condition: 'Kraftigt regn' }))).toBe('rain_heavy')
          expect(detectVibeKey(params({ condition: 'Störtregn' }))).toBe('rain_heavy')
        })

        it('returns rain (moderate) for other rain conditions', () => {
          expect(detectVibeKey(params({ condition: 'Måttligt regn' }))).toBe('rain')
          expect(detectVibeKey(params({ condition: 'Regnskurar' }))).toBe('rain')
          expect(detectVibeKey(params({ condition: 'Områden med regn' }))).toBe('rain')
        })

        it('rain_heavy + wind still returns rain_windy (wind takes priority)', () => {
          expect(detectVibeKey(params({ condition: 'Kraftigt regn', wind: 25 }))).toBe('rain_windy')
        })
      })
    })

    describe('fog conditions', () => {
      it('returns fog_icy for fog + freezing/icy conditions', () => {
        expect(detectVibeKey(params({ condition: 'Dimma', temp: -6 }))).toBe('fog_icy')
        expect(detectVibeKey(params({ condition: 'Underkyld dimma', temp: 0 }))).toBe('fog_icy')
      })

      it('returns fog_cold for fog + cold (but not freezing)', () => {
        expect(detectVibeKey(params({ condition: 'Dimma', temp: 2 }))).toBe('fog_cold')
        expect(detectVibeKey(params({ condition: 'Dis', temp: 0 }))).toBe('fog_cold')
      })

      it('returns fog for fog in mild weather', () => {
        expect(detectVibeKey(params({ condition: 'Dimma', temp: 10 }))).toBe('fog')
        expect(detectVibeKey(params({ condition: 'Dis', temp: 15 }))).toBe('fog')
      })
    })

    describe('sunny conditions', () => {
      it('returns sunny_freezing for sun + temp < -5', () => {
        expect(detectVibeKey(params({ condition: 'Soligt', temp: -6 }))).toBe('sunny_freezing')
        expect(detectVibeKey(params({ condition: 'Klart', temp: -10 }))).toBe('sunny_freezing')
      })

      it('returns sunny_cold_windy for sun + cold + wind', () => {
        expect(detectVibeKey(params({ condition: 'Sol', temp: 2, wind: 25 }))).toBe('sunny_cold_windy')
      })

      it('returns sunny_cold for sun + cold (0-5°C)', () => {
        expect(detectVibeKey(params({ condition: 'Soligt', temp: 2 }))).toBe('sunny_cold')
        expect(detectVibeKey(params({ condition: 'Klart', temp: 4 }))).toBe('sunny_cold')
      })

      it('returns sunny_mild for sun + mild (5-15°C)', () => {
        expect(detectVibeKey(params({ condition: 'Sol', temp: 10 }))).toBe('sunny_mild')
        expect(detectVibeKey(params({ condition: 'Soligt', temp: 14 }))).toBe('sunny_mild')
      })

      it('returns sunny for sun + warm (>= 15°C)', () => {
        expect(detectVibeKey(params({ condition: 'Sol', temp: 20 }))).toBe('sunny')
        expect(detectVibeKey(params({ condition: 'Klart', temp: 25 }))).toBe('sunny')
      })
    })

    describe('sun-aware fallbacks (Meteoblue)', () => {
      it('returns sun_3h for 3+ predicted sun hours in cloudy weather', () => {
        expect(detectVibeKey(params({ condition: 'Mulet', sunHours: 3 }))).toBe('sun_3h')
        expect(detectVibeKey(params({ condition: 'Molnigt', sunHours: 5 }))).toBe('sun_3h')
      })

      it('returns sun_2h for 2+ predicted sun hours', () => {
        expect(detectVibeKey(params({ condition: 'Mulet', sunHours: 2 }))).toBe('sun_2h')
      })

      it('returns sun_1h for 1+ predicted sun hours', () => {
        expect(detectVibeKey(params({ condition: 'Mulet', sunHours: 1 }))).toBe('sun_1h')
      })

      it('does not use sun fallback if WeatherAPI says sunny', () => {
        // WeatherAPI sunny takes priority over Meteoblue sun hours
        expect(detectVibeKey(params({ condition: 'Soligt', temp: 10, sunHours: 1 }))).toBe('sunny_mild')
      })
    })

    describe('cold/overcast fallbacks', () => {
      it('returns freezing_windy for freezing + wind', () => {
        expect(detectVibeKey(params({ temp: -6, wind: 25 }))).toBe('freezing_windy')
      })

      it('returns cold_damp_windy for cold + damp + wind', () => {
        expect(detectVibeKey(params({ temp: 2, humidity: 80, wind: 25 }))).toBe('cold_damp_windy')
      })

      it('returns cold_damp for cold + damp', () => {
        expect(detectVibeKey(params({ temp: 2, humidity: 80 }))).toBe('cold_damp')
      })

      it('returns cold_windy for cold + wind (no humidity)', () => {
        expect(detectVibeKey(params({ temp: 2, wind: 25 }))).toBe('cold_windy')
      })

      it('returns freezing for very cold without wind', () => {
        expect(detectVibeKey(params({ temp: -6 }))).toBe('freezing')
      })

      it('returns cold for cold (0-5°C)', () => {
        expect(detectVibeKey(params({ temp: 2 }))).toBe('cold')
      })

      it('returns damp for humid mild weather', () => {
        expect(detectVibeKey(params({ temp: 5, humidity: 80 }))).toBe('damp')
      })

      it('returns windy for windy mild weather', () => {
        expect(detectVibeKey(params({ temp: 10, wind: 25 }))).toBe('windy')
      })

      it('returns default for mild, calm, dry weather', () => {
        expect(detectVibeKey(params({ temp: 15, wind: 10, humidity: 50 }))).toBe('default')
      })
    })

    describe('priority order', () => {
      it('stormy beats everything', () => {
        expect(detectVibeKey(params({ condition: 'Snöfall', wind: 45 }))).toBe('stormy')
        expect(detectVibeKey(params({ condition: 'Regn', wind: 45 }))).toBe('stormy')
      })

      it('sleet beats snow', () => {
        expect(detectVibeKey(params({ condition: 'Snöblandat regn' }))).toBe('sleet')
      })

      it('rain beats fog', () => {
        // If both present, rain takes priority (rare but possible in condition text)
        expect(detectVibeKey(params({ condition: 'Regn och dimma' }))).toBe('rain')
      })

      it('sunny beats sun-aware fallbacks', () => {
        // temp: 10 is mild, so we get sunny_mild (which is still a sunny vibe)
        expect(detectVibeKey(params({ condition: 'Sol', sunHours: 5 }))).toBe('sunny_mild')
        // With warm temp, we get plain sunny
        expect(detectVibeKey(params({ condition: 'Sol', temp: 20, sunHours: 5 }))).toBe('sunny')
      })
    })
  })

  describe('getVibe helper', () => {
    it('returns short version for forecast', () => {
      const result = getVibe(params({ condition: 'Regn' }), 'short')
      expect(result).toBe('Ta paraply')
    })

    it('returns long version for current weather', () => {
      const result = getVibe(params({ condition: 'Regn' }), 'long')
      expect(result).toBe('Ta paraply')
    })

    it('returns different short/long for asymmetric vibes', () => {
      const short = getVibe(params({ condition: 'Snöfall' }), 'short')
      const long = getVibe(params({ condition: 'Snöfall' }), 'long')
      expect(short).toBe('Mysigt')
      expect(long).toBe('Mysigt ute')
    })
  })
})
