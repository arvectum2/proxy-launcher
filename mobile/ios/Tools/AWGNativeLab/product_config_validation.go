// Candidate configuration checking only. No socket or device.Up is allowed.
package main

import (
	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"net/netip"
	"os"
	"sync/atomic"
)

type validationOnlyBind struct{ attempted atomic.Bool }

var _ conn.Bind = (*validationOnlyBind)(nil)

func (b *validationOnlyBind) Open(uint16) ([]conn.ReceiveFunc, uint16, error) {
	b.attempted.Store(true)
	return nil, 0, os.ErrPermission
}
func (b *validationOnlyBind) Close() error { return nil }
func (b *validationOnlyBind) SetMark(mark uint32) error {
	if mark != 0 {
		return os.ErrPermission
	}
	return nil
}
func (b *validationOnlyBind) BatchSize() int { return 1 }
func (b *validationOnlyBind) Send([][]byte, conn.Endpoint) error {
	b.attempted.Store(true)
	return os.ErrPermission
}
func (b *validationOnlyBind) ParseEndpoint(raw string) (conn.Endpoint, error) {
	a, e := netip.ParseAddrPort(raw)
	if e != nil || a.Port() == 0 || a.Addr().Zone() != "" || a.Addr().Is4In6() || !a.Addr().IsGlobalUnicast() {
		return nil, os.ErrInvalid
	}
	return endpoint{a}, nil
}
func validateProductUAPI(raw []byte) bool {
	if len(raw) == 0 || len(raw) > 4096 {
		return false
	}
	b := &validationOnlyBind{}
	d := device.NewDevice(newPacketBridgeTUN(), b, device.NewLogger(device.LogLevelSilent, ""))
	err := d.IpcSet(string(raw))
	d.Close()
	return err == nil && !b.attempted.Load()
}
