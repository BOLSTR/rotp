require 'spec_helper'

RSpec.describe ROTP::TOTP do
  let(:now)   { Time.utc 2012,1,1 }
  let(:token) { '068212' }
  let(:totp)  { ROTP::TOTP.new 'JBSWY3DPEHPK3PXP' }

  describe '#at' do
    context 'with padding' do
      let(:token) { totp.at now }

      it 'is a string number' do
        expect(token).to eq '068212'
      end
    end

    context 'without padding' do
      let(:token) { totp.at now, false }

      it 'is an integer' do
        expect(token).to eq 68212
      end
    end

    context 'RFC compatibility' do
      let(:totp) { ROTP::TOTP.new('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ') }

      it 'matches the RFC documentation examples' do
        expect(totp.at 1111111111).to eq '050471'
        expect(totp.at 1234567890).to eq '005924'
        expect(totp.at 2000000000).to eq '279037'
      end

    end
  end

  describe '#verify' do
    let(:verification) { totp.verify token, now }

    context 'numeric token' do
      let(:token) { 68212 }

      it 'raises an error' do
        expect { verification }.to raise_error(ArgumentError)
      end
    end

    context 'unpadded string token' do
      let(:token) { '68212' }

      it 'is false' do
        expect(verification).to be_falsey
      end
    end

    context 'correctly padded string token' do
      it 'is true' do
        expect(verification).to be_truthy
      end
    end

    context 'RFC compatibility' do
      let(:totp)  { ROTP::TOTP.new 'wrn3pqx5uqxqvnqr' }

      before do
        Timecop.freeze now
      end

      context 'correct time based OTP' do
        let(:token) { '102705' }
        let(:now)   { Time.at 1297553958 }

        it 'is true' do
          expect(totp.verify('102705')).to be_truthy
        end
      end

      context 'wrong time based OTP' do
        it 'is false' do
          expect(totp.verify('102705')).to be_falsey
        end
      end
    end
  end

  describe '#provisioning_uri' do
    let(:uri)    { totp.provisioning_uri('mark@percival') }
    let(:params) { CGI::parse URI::parse(uri).query }

    context 'without issuer' do
      it 'has the correct format' do
        expect(uri).to match %r{\Aotpauth:\/\/totp.+}
      end

      it 'includes the secret as parameter' do
        expect(params['secret'].first).to eq 'JBSWY3DPEHPK3PXP'
      end
    end

    context 'with default digits' do
      it 'does does not include digits parameter' do
        expect(params['digits'].first).to be_nil
      end
    end

    context 'with non-default digits' do
      let(:totp)  { ROTP::TOTP.new 'JBSWY3DPEHPK3PXP', digits: 8 }

      it 'does does not include digits parameter' do
        expect(params['digits'].first).to eq '8'
      end
    end

    context 'with issuer' do
      let(:totp)  { ROTP::TOTP.new 'JBSWY3DPEHPK3PXP', issuer: 'FooCo' }

      it 'has the correct format' do
        expect(uri).to match %r{\Aotpauth:\/\/totp/FooCo:.+}
      end

      it 'includes the secret as parameter' do
        expect(params['secret'].first).to eq 'JBSWY3DPEHPK3PXP'
      end

      it 'includes the issuer as parameter' do
        expect(params['issuer'].first).to eq 'FooCo'
      end
    end

    context 'with custom interval' do
      let(:totp)  { ROTP::TOTP.new 'JBSWY3DPEHPK3PXP', interval: 60 }

      it 'has the correct format' do
        expect(uri).to match %r{\Aotpauth:\/\/totp.+}
      end

      it 'includes the secret as parameter' do
        expect(params['secret'].first).to eq 'JBSWY3DPEHPK3PXP'
      end

      it 'includes the interval as period parameter' do
        expect(params['period'].first).to eq '60'
      end
    end

    context 'with custom digest' do
      let(:totp)  { ROTP::TOTP.new 'JBSWY3DPEHPK3PXP', digest: 'sha256' }

      it 'has the correct format' do
        expect(uri).to match %r{\Aotpauth:\/\/totp.+}
      end

      it 'includes the secret as parameter' do
        expect(params['secret'].first).to eq 'JBSWY3DPEHPK3PXP'
      end

      it 'includes the digest as algorithm parameter' do
        expect(params['algorithm'].first).to eq 'SHA256'
      end
    end

  end

  describe '#verify_with_drift' do
    let(:verification) { totp.verify_with_drift token, drift, now }
    let(:drift) { 0 }


    context 'slightly old number' do
      let(:token) { totp.at now - 30 }
      let(:drift) { 60 }

      it 'is true' do
        expect(verification).to be_truthy
      end
    end

    context 'slightly new number' do
      let(:token) { totp.at now + 60 }
      let(:drift) { 60 }

      it 'is true' do
        expect(verification).to be_truthy
      end
    end

    context 'outside of drift range' do
      let(:token) { totp.at now - 60 }
      let(:drift) { 30 }

      it 'is false' do
        expect(verification).to be_falsey
      end
    end

    context 'drift is not multiple of TOTP interval' do
      context 'slightly old number' do
        let(:token) { totp.at now - 45 }
        let(:drift) { 45 }

        it 'is true' do
          expect(verification).to be_truthy
        end
      end

      context 'slightly new number' do
        let(:token) { totp.at now + 40 }
        let(:drift) { 40 }

        it 'is true' do
          expect(verification).to be_truthy
        end
      end
    end
  end

  describe '#verify_with_drift_and_prior' do
    let(:verification) { totp.verify_with_drift_and_prior token, drift, prior, now }
    let(:drift) { 0 }
    let(:prior) { nil }

    context 'with a prior verify' do
      let(:prior) { totp.verify_with_drift_and_prior '068212', 0, nil, now }

      it 'returns a timecode' do
        expect(prior).to be_kind_of(Integer)
        expect(prior).to be_within(30).of(now.to_i)
      end

      context 'reusing same token' do
        it 'is false' do
          expect(verification).to be_falsy
        end
      end

      context 'newer token' do
        let(:token) { totp.at now + 40 }
        let(:drift) { 40 }

        it 'is true' do
          expect(verification).to be_kind_of(Integer)
          expect(verification).to be_within(30).of(now.to_i)
          expect(verification).to be_truthy
        end
      end

      context 'older token' do
        let(:token) { totp.at now - 40 }
        let(:drift) { 40 }

        it 'is false' do
          expect(verification).to be_falsy
        end
      end
    end
  end

  describe '#now' do
    before do
      Timecop.freeze now
    end

    context 'Google Authenticator' do
      let(:totp) { ROTP::TOTP.new 'wrn3pqx5uqxqvnqr' }
      let(:now)  { Time.at 1297553958 }

      it 'matches the known output' do
        expect(totp.now).to eq '102705'
      end
    end

    context 'Dropbox 26 char secret output' do
      let(:totp) { ROTP::TOTP.new 'tjtpqea6a42l56g5eym73go2oa' }
      let(:now)  { Time.at 1378762454 }

      it 'matches the known output' do
        expect(totp.now).to eq '747864'
      end
    end
  end

end
